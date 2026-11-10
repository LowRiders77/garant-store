// Garant-PO v6 - local-only multi-threaded host for Windows PowerShell 5.1 / .NET Framework 4.5+
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

namespace GarantPO {
 public sealed class Host {
  private readonly string root, dataRoot, state, logs, downloads, userDownloads, drivers, ui, token, bootstrapFile;
  private readonly bool embedded, tokenSuppliedByClient;
  private readonly HttpListener listener = new HttpListener();
  private readonly object gate = new object(), logGate = new object(), sizeGate = new object();
  private Process worker;
  private bool stopping = false;
  private long lastSize = 0;
  private DateTime lastSizeTime = DateTime.UtcNow;
  private string lastFile = "";
  private int port;
  public Host(string path, string dataPath, bool embeddedMode, string bootstrapPath) : this(path,dataPath,embeddedMode,bootstrapPath,"") {}
  public Host(string path, string dataPath, bool embeddedMode, string bootstrapPath, string clientToken) {
   root = Path.GetFullPath(path); dataRoot = Path.GetFullPath(dataPath);
   embedded = embeddedMode; bootstrapFile = bootstrapPath ?? "";
   state = Path.Combine(dataRoot, "State"); logs = Path.Combine(dataRoot, "Logs");
   // Packages that an elevated worker installs are always downloaded into the
   // engine's own data root. The user's Downloads folder only receives copies.
   downloads = Path.Combine(dataRoot,"Downloads");
   userDownloads = ConfiguredPath("GARANT_PO_DOWNLOAD_DIR",downloads); drivers = ConfiguredPath("GARANT_PO_DRIVER_DIR",Path.Combine(dataRoot,"Drivers"));
   ui = Path.Combine(root,"UI","index.html");
   Directory.CreateDirectory(state); Directory.CreateDirectory(logs);
   Directory.CreateDirectory(downloads); Directory.CreateDirectory(userDownloads); Directory.CreateDirectory(drivers);
   Directory.CreateDirectory(ConfiguredPath("GARANT_PO_LIBRARY_DIR",Path.Combine(dataRoot,"Libraries")));
   tokenSuppliedByClient = IsStrongToken(clientToken);
   token = tokenSuppliedByClient ? clientToken : Guid.NewGuid().ToString("N")+Guid.NewGuid().ToString("N");
  }
  // A client-supplied token must be long random hex; anything weaker is ignored.
  private static bool IsStrongToken(string value) {
   if (String.IsNullOrEmpty(value) || value.Length < 32 || value.Length > 128) return false;
   foreach (char ch in value) if (!Uri.IsHexDigit(ch)) return false;
   return true;
  }
  public void Run() {
   for (int attempt=0;attempt<5;attempt++) {
    TcpListener probe = new TcpListener(IPAddress.Loopback,0);
    probe.Start(); port = ((IPEndPoint)probe.LocalEndpoint).Port; probe.Stop();
    listener.Prefixes.Clear(); listener.Prefixes.Add("http://127.0.0.1:" + port + "/");
    try { listener.Start(); break; }
    catch (HttpListenerException) { if (attempt==4) throw; }
   }
   string url = "http://127.0.0.1:" + port + "/";
   Log("SERVER START version=6.0 address="+url+" pid="+Process.GetCurrentProcess().Id);
   Console.WriteLine("GARANT-PO 6.0 | "+url);
   if (!String.IsNullOrWhiteSpace(bootstrapFile)) {
    string temp=bootstrapFile+"."+Guid.NewGuid().ToString("N")+".tmp";
    // When the WPF client generated the token it already knows it; never persist it to disk.
    object info = tokenSuppliedByClient
     ? (object)new {ok=true,version="6.0",url=url,pid=Process.GetCurrentProcess().Id}
     : (object)new {ok=true,version="6.0",url=url,token=token,pid=Process.GetCurrentProcess().Id};
    File.WriteAllText(temp,Serializer().Serialize(info),Encoding.UTF8);
    if(File.Exists(bootstrapFile)) File.Delete(bootstrapFile);
    File.Move(temp,bootstrapFile);
   }
   if (!embedded) {
    Console.WriteLine("The command window must stay open while using the web interface.");
    // The token travels in the URL fragment: browsers never send the fragment to the server.
    try { Process.Start(url+"#t="+token); } catch { Console.WriteLine("Open the URL in your browser: "+url+"#t="+token); }
   }
   try {
    while (!stopping && listener.IsListening) {
     HttpListenerContext ctx;
     try {ctx = listener.GetContext();} catch (HttpListenerException) { break; }
     catch (ObjectDisposedException) { break; }
     ThreadPool.QueueUserWorkItem(delegate(object obj) { Handle((HttpListenerContext)obj); },ctx);
    }
   } finally { stopping=true; try{listener.Close();}catch{} if(!String.IsNullOrWhiteSpace(bootstrapFile)){try{File.Delete(bootstrapFile);}catch{}} Log("SERVER STOP"); }
  }
  private void Log(string message) {
   lock(logGate) {
    try { File.AppendAllText(Path.Combine(logs,"Garant-PO-Server.log"),"["+DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff")+"] "+message+Environment.NewLine, Encoding.UTF8); } catch {}
   }
  }
  private void UIlog(string message) {
   lock(logGate) {
    try { File.AppendAllText(Path.Combine(logs,"Garant-PO-Interface.log"),"["+DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff")+"] "+message+Environment.NewLine, Encoding.UTF8); } catch {}
   }
  }
  private static JavaScriptSerializer Serializer() {JavaScriptSerializer j=new JavaScriptSerializer();j.MaxJsonLength=8*1024*1024;return j;}
  private static string ConfiguredPath(string variable,string fallback) {
   string value=Environment.GetEnvironmentVariable(variable);
   return String.IsNullOrWhiteSpace(value) ? fallback : Path.GetFullPath(value);
  }
  private object ParseFile(string path, object fallback) {
   try { if(File.Exists(path)) return Serializer().DeserializeObject(File.ReadAllText(path,Encoding.UTF8)); }
   catch (Exception ex) { Log("JSON_READ " + Path.GetFileName(path) + " " + ex.Message); }
   return fallback;
  }
  private static Dictionary<string,object> Dict(object value) { return value as Dictionary<string,object> ?? new Dictionary<string,object>(); }
  private static string S(object x) { return x == null ? "" : Convert.ToString(x,System.Globalization.CultureInfo.InvariantCulture); }
  private static object Field(Dictionary<string,object> map,string key, object fallback) {object val; return map.TryGetValue(key,out val) && val!=null ? val : fallback;}
  private static bool B(object x) { return x is bool && (bool)x; }
  private static long L(object x) { long result; return long.TryParse(S(x),out result) ? result : 0; }
  private static string ReadTail(string path, int maxLines) {
   try {
    if (!File.Exists(path)) return "";
    using (FileStream f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))
    using (StreamReader r=new StreamReader(f, Encoding.UTF8, true)) {
     string body=r.ReadToEnd(); string[] lines=body.Split(new [] {'\n'});
     int start=Math.Max(0,lines.Length-maxLines);return String.Join("\n",lines,start,lines.Length-start);
    }
   }catch{return "";}
  }
  private Dictionary<string,object> Snapshot() {
   Dictionary<string,object> status=Dict(ParseFile(Path.Combine(state,"status.json"),new Dictionary<string,object>()));
   object rawDevices = ParseFile(Path.Combine(state,"devices.json"), new object[0]);
   ArrayList items = new ArrayList();
   IEnumerable enumerable=rawDevices as IEnumerable;
   if(enumerable!=null && !(rawDevices is string)) foreach(object o in enumerable) {
    Dictionary<string,object> d=o as Dictionary<string,object>;
    if(d!=null && !String.IsNullOrEmpty(S(Field(d,"instanceId","")))) items.Add(d);
   }
   Process p; lock (gate) {p=worker;}
   bool alive=false;
   if(p!=null) {try{alive=!p.HasExited;}catch{}}
   if(B(Field(status,"running",false)) && !alive) {
    status["running"]=false;
    status["phase"]="Завершено без подтверждения";
    status["message"]="Процесс завершился. Проверь журнал и запусти сканирование.";
   }
   if(alive) status["running"]=true;
   // Driver progress is reported by the worker. Disk size remains a fallback if its JSON update is delayed.
   string current=Path.GetFileName(S(Field(status,"current","")));
   if(B(Field(status,"running",false)) && current.Length>0 && S(Field(status,"phase",""))=="Загрузка") {
    string partial=Path.Combine(downloads,current+".partial");
    try {
     if(File.Exists(partial)) {
      long bytes=new FileInfo(partial).Length;
      if(bytes>L(Field(status,"bytes",0))) status["bytes"]=bytes;
      lock(sizeGate){
       DateTime now=DateTime.UtcNow;
       double seconds=Math.Max(.25,(now-lastSizeTime).TotalSeconds);
       if(current==lastFile && bytes>lastSize && L(Field(status,"speedBps",0))==0) status["speedBps"]=(long)((bytes-lastSize)/seconds);
       lastFile=current;lastSize=bytes;lastSizeTime=now;
      }
      long expected=L(Field(status,"expectedBytes",0));
      if(expected>0) status["percent"]=Math.Round(Math.Min(100.0,100.0*bytes/expected),1);
     }
    }catch{}
   }
   bool scanned=B(Field(status,"scanned",false)) || File.Exists(Path.Combine(state,"scan.flag"));
   string phase=S(Field(status,"phase", ""));
   string action=S(Field(status,"action",""));
   bool operationView=action.StartsWith("update-",StringComparison.OrdinalIgnoreCase) || action.StartsWith("selected-",StringComparison.OrdinalIgnoreCase) || action=="network" || action=="libraries" || action=="restore-point" || action=="windows-update-repair";
   if(scanned && !operationView && items.Count==0 && !B(Field(status,"running",false)) && L(Field(status,"errors",0))==0 && String.IsNullOrWhiteSpace(S(Field(status,"lastError",""))) && phase!="Ошибка" && phase!="Ошибка процесса" && phase!="Прервано" && phase!="Завершено без подтверждения" && phase!="Завершено с предупреждением") {
    status["allInstalled"]=true;
    status["message"]="Все необходимые драйверы установлены. Проблемных устройств не обнаружено.";
    if(phase=="" || phase=="Ожидание" || phase=="Готово") status["phase"]="Готово";
   }
   // Keep the API contract complete before the first scan, when no status.json exists yet.
   if(!status.ContainsKey("running") || status["running"]==null) status["running"]=false;
   if(!status.ContainsKey("phase") || status["phase"]==null) status["phase"]=scanned ? "Готово" : "Ожидание";
   if(!status.ContainsKey("message") || status["message"]==null) status["message"]=scanned ? "Проверка завершена. Выберите нужные устройства." : "Нажмите «Сканировать», чтобы проверить устройства.";
   if(!status.ContainsKey("percent") || status["percent"]==null) status["percent"]=-1;
   Dictionary<string,object> result=new Dictionary<string,object>();
   result["status"]=status;
   result["devices"]=items;
   result["logs"]=ReadTail(Path.Combine(logs,"Garant-PO-Latest.log"),90).Split(new[]{'\n'});
   result["proxyConfigured"]=File.Exists(Path.Combine(root,"Proxy.txt")) && ReadTail(Path.Combine(root,"Proxy.txt"),10).Contains("://");
   result["version"]="6.0";
   result["scanned"]=scanned;
   result["serverPid"]=Process.GetCurrentProcess().Id;
   result["serverTime"]=DateTime.Now.ToString("HH:mm:ss");
   result["os"]=Environment.OSVersion.VersionString;
   return result;
  }
  private void Write(HttpListenerContext c,byte[] bytes,string mime,int code) {
   HttpListenerResponse r=c.Response;
   r.StatusCode=code; r.ContentType=mime;
   r.Headers["Cache-Control"]="no-store, no-cache, must-revalidate";
   r.Headers["X-Content-Type-Options"]="nosniff";
   r.ContentLength64=bytes.Length;
   r.OutputStream.Write(bytes,0,bytes.Length);r.Close();
  }
  private void JSON(HttpListenerContext c,object value,int code) {Write(c,Encoding.UTF8.GetBytes(Serializer().Serialize(value)),"application/json; charset=utf-8",code);}
  private static string Body(HttpListenerContext c) {
   if(c.Request.ContentLength64>65536) throw new InvalidOperationException("Request too large");
   using(StreamReader r=new StreamReader(c.Request.InputStream,Encoding.UTF8)){
    string str=r.ReadToEnd();if(str.Length>65536)throw new InvalidOperationException("Request too large");return str;
   }
  }
  private bool Authorized(HttpListenerContext c) {
   if (FixedTimeEquals(c.Request.Headers["X-Garant-Token"],token)) return true;
   // EventSource and download links cannot set headers; allow a query token for read-only GET routes only.
   return c.Request.HttpMethod=="GET" && FixedTimeEquals(c.Request.QueryString["t"],token);
  }
  private static bool FixedTimeEquals(string a,string b) {
   if (a==null || b==null || a.Length!=b.Length) return false;
   int diff=0; for (int i=0;i<a.Length;i++) diff|=a[i]^b[i];
   return diff==0;
  }
  private void Attachment(HttpListenerContext c,byte[] bytes,string name,string mime) {
   c.Response.Headers.Add("Content-Disposition","attachment; filename=\""+name+"\"");
   Write(c,bytes,mime,200);
  }
  private byte[] Diagnostics() {
   using(MemoryStream m=new MemoryStream()) {
    using(ZipArchive z=new ZipArchive(m,ZipArchiveMode.Create,true)) {
     string[] files={"Garant-PO-Latest.log","Garant-PO-Interface.log","Garant-PO-Server.log","Worker-stdout.log","Worker-stderr.log","Remaining.csv","Missing-DRP-Links.txt","Garant-PO-Server-Startup-Error.log"};
     foreach(string name in files) AddToZip(z,Path.Combine(logs,name),name);
     AddToZip(z,Path.Combine(root,"Core.ps1"),"Engine/Core.ps1");
     AddToZip(z,Path.Combine(root,"Worker.ps1"),"Engine/Worker.ps1");
     AddToZip(z,Path.Combine(root,"Catalog.ps1"),"Engine/Catalog.ps1");
     AddToZip(z,Path.Combine(root,"VendorGpu.ps1"),"Engine/VendorGpu.ps1");
     AddToZip(z,Path.Combine(root,"DRP_Known_Links.csv"),"Engine/DRP_Known_Links.csv");
     AddToZip(z,Path.Combine(root,"Updates.ps1"),"Engine/Updates.ps1");
     AddToZip(z,Path.Combine(root,"UpdateCatalog.ps1"),"Engine/UpdateCatalog.ps1");
     AddToZip(z,Path.Combine(root,"Libraries.ps1"),"Engine/Libraries.ps1");
     AddToZip(z,Path.Combine(root,"NetworkRepair.ps1"),"Engine/NetworkRepair.ps1");
     AddToZip(z,Path.Combine(root,"RestorePoint.ps1"),"Engine/RestorePoint.ps1");
     AddToZip(z,Path.Combine(root,"WindowsUpdateRepair.ps1"),"Engine/WindowsUpdateRepair.ps1");
     AddToZip(z,Path.Combine(root,"Selected.ps1"),"Engine/Selected.ps1");
     string paths="Downloads="+userDownloads+Environment.NewLine+"EngineDownloads="+downloads+Environment.NewLine+"Drivers="+drivers+Environment.NewLine+"Libraries="+ConfiguredPath("GARANT_PO_LIBRARY_DIR",Path.Combine(dataRoot,"Libraries"))+Environment.NewLine;
     byte[] pathBytes=Encoding.UTF8.GetBytes(paths);
     var pathEntry=z.CreateEntry("Garant-PO-Paths.txt",CompressionLevel.Optimal);
     using(var pathStream=pathEntry.Open())pathStream.Write(pathBytes,0,pathBytes.Length);
     string[] stateFiles={"status.json","devices.json","curl_diagnostics.log","curl_stderr.txt","curl_headers.txt","system-profile.json","device-session.json","device-history.json"};
     foreach(string name in stateFiles)AddToZip(z,Path.Combine(state,name),"State/"+name);
    }
    return m.ToArray();
   }
  }
  private void AddToZip(ZipArchive archive,string path,string entry) {
   try {
    if(!File.Exists(path))return;
    ZipArchiveEntry target=archive.CreateEntry(entry,CompressionLevel.Fastest);
    using(Stream dest=target.Open())
    using(FileStream src=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))src.CopyTo(dest);
   } catch (Exception e){Log("ZIP_SKIP "+Path.GetFileName(path)+" "+e.Message);}
  }
  private void Events(HttpListenerContext c) {
   HttpListenerResponse r=c.Response;
   r.StatusCode=200;r.ContentType="text/event-stream; charset=utf-8";
   r.Headers.Add("Cache-Control","no-cache");
   r.Headers.Add("X-Accel-Buffering","no");
   r.SendChunked=true;
   Log("EVENTS CONNECT");
   try {
    for(int i=0;i<7200 && !stopping;i++) {
     string payload="event: status\ndata: "+Serializer().Serialize(Snapshot())+"\n\n";
     byte[] bytes=Encoding.UTF8.GetBytes(payload);
     r.OutputStream.Write(bytes,0,bytes.Length);r.OutputStream.Flush();
     Thread.Sleep(1000);
    }
   } catch(IOException){} catch(HttpListenerException){} catch(ObjectDisposedException){}
   catch(Exception ex){Log("EVENTS ERROR "+ex.Message);}
   finally{try{r.Close();}catch{} Log("EVENTS DISCONNECT");}
  }
  private void Handle(HttpListenerContext c) {
   Stopwatch timer=Stopwatch.StartNew();
   string path="?";int code=200;
   try {
    if(c.Request.RemoteEndPoint!=null && !IPAddress.IsLoopback(c.Request.RemoteEndPoint.Address)) {JSON(c,new{error="Local access only"},403);return;}
    path=c.Request.Url.AbsolutePath;
    string method=c.Request.HttpMethod;
    if(method=="GET" && path=="/api/health"){JSON(c,new{ok=true,version="6.0",timestamp=DateTime.Now.ToString("o")},200);return;}
    if(method=="GET" && path=="/"){
     // The embedded WPF client has its own window; the browser page exists only for standalone Garant-PO.
     // The page itself carries no secret: the token arrives in the URL fragment.
     if(embedded){JSON(c,new{error="Маршрут не найден"},404);return;}
     string html=File.ReadAllText(ui,Encoding.UTF8).Replace("__TOKEN__","");
     Write(c,Encoding.UTF8.GetBytes(html),"text/html; charset=utf-8",200);
     return;
    }
    // Every other route, including read-only status, logs and diagnostics, requires the session token.
    if(!Authorized(c)){JSON(c,new{error="Access denied"},403);return;}
    if(method=="GET" && path=="/api/events")Events(c);
    else if(method=="GET" && path=="/api/status")JSON(c,Snapshot(),200);
    else if(method=="GET" && path=="/api/diagnostics") {byte[] bytes=Diagnostics();Attachment(c,bytes,"Garant-PO-Diagnostics.zip","application/zip");Log("DIAGNOSTICS "+bytes.Length+" bytes");}
    else if(method=="GET" && path=="/api/report") {
     string f=Path.Combine(logs,"Remaining.csv");
     if(File.Exists(f))Attachment(c,File.ReadAllBytes(f),"Garant-PO-Remaining.csv","text/csv; charset=utf-8");
     else JSON(c,new{error="Отчёт ещё не создан"},404);
    }
    else if(method=="GET" && path=="/api/ui-log"){
     string f=Path.Combine(logs,"Garant-PO-Interface.log");
     Attachment(c,Encoding.UTF8.GetBytes(ReadTail(f,5000)),"Garant-PO-Interface.log","text/plain; charset=utf-8");
    }
    else if(method=="POST" && path.StartsWith("/api/")){
     if(path=="/api/action"){
      Dictionary<string,object> data=Dict(Serializer().DeserializeObject(Body(c)));
      string action=S(Field(data,"action",""));
      if(Array.IndexOf(new[]{"scan","auto","download","gpu","local","network","restore-point","windows-update-repair","update-scan","update-install","libraries","selected-install","selected-download"},action)<0) {JSON(c,new{error="Неизвестная команда"},400);return;}
      int pid;
      lock(gate){
       if(worker!=null && !worker.HasExited){JSON(c,new{error="Операция уже выполняется"},409);return;}
       ArrayList ids=new ArrayList();
       IEnumerable arr=Field(data,"ids",new object[0]) as IEnumerable;
       if(arr!=null && !(arr is string))foreach(object item in arr){if(ids.Count<100 && S(item).Length<=1024)ids.Add(S(item));}
       File.WriteAllText(Path.Combine(state,"selection.json"),Serializer().Serialize(ids),Encoding.UTF8);
       try{File.Delete(Path.Combine(state,"cancel.flag"));}catch{}
       // Preserve the completed inventory for maintenance actions. Only a new scan
       // invalidates the previous result set.
       if(action=="scan" || action=="update-scan") {try{File.Delete(Path.Combine(state,"scan.flag"));}catch{}}
       var pending=new Dictionary<string,object>();
       pending["running"]=true;pending["action"]=action;pending["phase"]="Подготовка";
       pending["message"]="Запуск задачи";pending["total"]=0;pending["remaining"]=0;
       pending["bytes"]=0;pending["expectedBytes"]=0;pending["current"]="";pending["percent"]=-1;
       pending["started"]=DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");pending["scanned"]=File.Exists(Path.Combine(state,"scan.flag"));
       File.WriteAllText(Path.Combine(state,"status.json"),Serializer().Serialize(pending),Encoding.UTF8);
       if(action=="scan" || action=="update-scan") File.WriteAllText(Path.Combine(state,"devices.json"),Serializer().Serialize(new object[0]),Encoding.UTF8);
       ProcessStartInfo psi=new ProcessStartInfo();
       psi.FileName=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32","WindowsPowerShell","v1.0","powershell.exe");
       if(String.Equals(action,"network",StringComparison.OrdinalIgnoreCase))
        psi.Arguments="-NoLogo -NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(root,"NetworkRepair.ps1")+"\"";
       else if(String.Equals(action,"restore-point",StringComparison.OrdinalIgnoreCase))
        psi.Arguments="-NoLogo -NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(root,"RestorePoint.ps1")+"\"";
       else if(String.Equals(action,"windows-update-repair",StringComparison.OrdinalIgnoreCase))
        psi.Arguments="-NoLogo -NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(root,"WindowsUpdateRepair.ps1")+"\"";
       else if(action=="selected-install" || action=="selected-download")
        psi.Arguments="-NoLogo -NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(root,"Selected.ps1")+"\" -Mode "+(action=="selected-install"?"install":"download");
       else if(action=="libraries")
        psi.Arguments="-NoLogo -NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(root,"Libraries.ps1")+"\"";
       else if(action.StartsWith("update-",StringComparison.OrdinalIgnoreCase))
        psi.Arguments="-NoLogo -NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(root,"Updates.ps1")+"\" -Mode "+(action=="update-scan"?"scan":"install");
       else if(Array.IndexOf(new[]{"scan","auto","download","gpu","local"},action)>=0)
        psi.Arguments="-NoLogo -NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(root,"Worker.ps1")+"\" -Action "+action;
       else {JSON(c,new{error="Для команды не настроен обработчик"},400);return;}
       psi.WorkingDirectory=root;psi.UseShellExecute=false;psi.CreateNoWindow=true;
       psi.RedirectStandardOutput=true;psi.RedirectStandardError=true;
       worker=new Process();worker.StartInfo=psi;
       worker.OutputDataReceived += delegate(object o,DataReceivedEventArgs e){if(e.Data!=null)AppendWorker("Worker-stdout.log",e.Data);};
       worker.ErrorDataReceived += delegate(object o,DataReceivedEventArgs e){if(e.Data!=null)AppendWorker("Worker-stderr.log",e.Data);};
       worker.Start();worker.BeginOutputReadLine();worker.BeginErrorReadLine();pid=worker.Id;
      }
      Log("ACTION "+action+" pid="+pid);
      JSON(c,new{ok=true,action=action,pid=pid},200);
     }
     else if(path=="/api/cancel"){
      lock(gate){if(worker==null||worker.HasExited){JSON(c,new{error="Нет работающей операции"},409);return;}File.WriteAllText(Path.Combine(state,"cancel.flag"),"stop");}
      JSON(c,new{ok=true,message="Остановка запрошена"},200);Log("CANCEL");
     }
     else if(path=="/api/ui-event"){
      object payload=Serializer().DeserializeObject(Body(c));
      ArrayList events=new ArrayList();
      object[] many=payload as object[];
      if(many!=null)events.AddRange(many);else events.Add(payload);
      foreach(object item in events){Dictionary<string,object> d=Dict(item);string eventName=S(Field(d,"event",""));string detail=S(Field(d,"detail",""));if(eventName.Length>120)eventName=eventName.Substring(0,120);if(detail.Length>1000)detail=detail.Substring(0,1000);UIlog(eventName+" | "+detail);}
      JSON(c,new{ok=true},200);
     }
     else if(path=="/api/open-drivers") {Process.Start("explorer.exe","\""+drivers+"\"");JSON(c,new{ok=true},200);}
     else if(path=="/api/exit"){
      lock(gate){if(worker!=null&&!worker.HasExited){JSON(c,new{error="Дождись завершения установки"},409);return;}}
      JSON(c,new{ok=true},200);stopping=true;listener.Stop();
     }
     else JSON(c,new{error="Маршрут не найден"},404);
    }
    else JSON(c,new{error="Маршрут не найден"},404);
   }catch(Exception ex){code=500;Log("API ERROR "+path+" "+ex.ToString());try{JSON(c,new{error=ex.Message},500);}catch{}}
   finally{
    timer.Stop();
    if(path!="/api/status" && path!="/api/events" || timer.ElapsedMilliseconds>1500)
     Log("HTTP "+c.Request.HttpMethod+" "+path+" code="+code+" duration="+timer.ElapsedMilliseconds+"ms");
   }
  }
  private void AppendWorker(string name,string text) {
   lock(logGate) {
    try{File.AppendAllText(Path.Combine(logs,name),text+Environment.NewLine,Encoding.UTF8);}catch{}
   }
  }
 }
}
