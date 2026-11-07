# Garant Store v0.11.0
# Windows PowerShell 5.1 compatible.
# IMPORTANT: this source file is ASCII-only by design.
# Russian strings are Base64 UTF-8 decoded at runtime, avoiding code-page bugs.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Native GDI+ gradient surfaces: real-time, DPI-compatible, no external runtime.
if (-not ('GarantUi.GradientPanel' -as [type])) {
Add-Type -ReferencedAssemblies @('System.Windows.Forms.dll','System.Drawing.dll') -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
namespace GarantUi {
    public static class Shapes {
        public static GraphicsPath Rounded(Rectangle r, int rad) {
            GraphicsPath gp = new GraphicsPath();
            int d = Math.Min(Math.Min(rad * 2, r.Width), r.Height);
            if (d < 2) { gp.AddRectangle(r); return gp; }
            gp.AddArc(r.X,r.Y,d,d,180,90);
            gp.AddArc(r.Right-d,r.Y,d,d,270,90);
            gp.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);
            gp.AddArc(r.X,r.Bottom-d,d,d,90,90);
            gp.CloseFigure(); return gp;
        }
    }
    public class GradientPanel : Panel {
        public Color ColorA {get;set;}
        public Color ColorB {get;set;}
        public Color BorderColor {get;set;}
        public Color GlowColor {get;set;}
        public int Corner {get;set;}
        public bool Glow {get;set;}
        public GradientPanel() {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
            ColorA=Color.FromArgb(27,39,59); ColorB=Color.FromArgb(17,24,39);
            BorderColor=Color.FromArgb(65,91,115); GlowColor=Color.FromArgb(25,189,159);
            Corner=20; Glow=false; BackColor=Color.FromArgb(17,24,39);
        }
        // Clip the native child window itself, not just its paint brush.
        // Without this, square WinForms control backgrounds leak through
        // the transparent-looking corners as black rectangles.
        protected override void OnSizeChanged(EventArgs e) {
            base.OnSizeChanged(e);
            UpdateRoundedRegion();
        }
        protected override void OnHandleCreated(EventArgs e) {
            base.OnHandleCreated(e);
            UpdateRoundedRegion();
        }
        void UpdateRoundedRegion() {
            if (Width < 2 || Height < 2 || IsDisposed) return;
            using (GraphicsPath gp=Shapes.Rounded(new Rectangle(0,0,Width,Height),Corner)) {
                Region next=new Region(gp);
                Region previous=Region;
                Region=next;
                if (previous!=null) previous.Dispose();
            }
        }
        protected override void OnPaintBackground(PaintEventArgs e) {
            if (Width < 2 || Height < 2) return;
            e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
            Rectangle r = new Rectangle(0,0,Width-1,Height-1);
            using(GraphicsPath gp=Shapes.Rounded(r,Corner)) {
                using(SolidBrush b=new SolidBrush(ColorA))
                    e.Graphics.FillPath(b,gp);
                if (Glow) {
                    GraphicsState old=e.Graphics.Save(); e.Graphics.SetClip(gp);
                    for(int i=6;i>=1;i--) {
                        int diameter=105+i*28;
                        int alpha=(int)(9.0/(i*0.7));
                        using(SolidBrush orb=new SolidBrush(Color.FromArgb(Math.Min(28,alpha),GlowColor))) {
                            e.Graphics.FillEllipse(orb, Width-170-diameter/2, -diameter/2, diameter,diameter);
                        }
                    }
                    e.Graphics.Restore(old);
                }
                using(Pen line=new Pen(BorderColor,1)) e.Graphics.DrawPath(line,gp);
            }
        }
    }
    public class FastGrid : DataGridView {
        public FastGrid() { DoubleBuffered = true; }
    }
    // Icons are ancillary: search and installation never wait for network artwork.
    // Known domains are curated and never derived from untrusted package metadata.
    public static class AppIcons {
        static readonly System.Collections.Concurrent.ConcurrentDictionary<string,Bitmap> images =
            new System.Collections.Concurrent.ConcurrentDictionary<string,Bitmap>(StringComparer.OrdinalIgnoreCase);
        static readonly System.Collections.Concurrent.ConcurrentDictionary<string,byte> queued =
            new System.Collections.Concurrent.ConcurrentDictionary<string,byte>(StringComparer.OrdinalIgnoreCase);
        static readonly System.Threading.SemaphoreSlim slots = new System.Threading.SemaphoreSlim(3);
        static int revision;
        public static bool EnableNetwork { get; set; }
        public static int Revision { get { return System.Threading.Volatile.Read(ref revision); } }
        static readonly System.Collections.Generic.Dictionary<string,string> known =
            new System.Collections.Generic.Dictionary<string,string>(StringComparer.OrdinalIgnoreCase) {
                {"WhatsApp","whatsapp.com"},{"WhatsApp Beta","whatsapp.com"},
                {"Telegram","telegram.org"},{"Telegram Desktop","telegram.org"},
                {"ChatGPT","chatgpt.com"},{"CapCut","capcut.com"},{"7-Zip","7-zip.org"},
                {"Google Chrome","google.com"},{"Mozilla Firefox","mozilla.org"},
                {"Microsoft Edge","microsoft.com"},{"VLC","videolan.org"},
                {"VLC media player","videolan.org"},{"Discord","discord.com"},
                {"Signal","signal.org"},{"Spotify","spotify.com"},
                {"OBS Studio","obsproject.com"},{"Visual Studio Code","code.visualstudio.com"},
                {"Notepad++","notepad-plus-plus.org"},{"Git","git-scm.com"},
                {"Git for Windows","git-scm.com"},{"WinRAR","rarlab.com"},
                {"Zoom","zoom.us"},{"Zoom Workplace","zoom.us"},
                {"Microsoft Teams","microsoft.com"},{"Microsoft To Do","todo.microsoft.com"},
                {"Microsoft PowerToys","learn.microsoft.com"},{"OneDrive","onedrive.live.com"},
                {"Steam","steampowered.com"},{"Slack","slack.com"},
                {"Dropbox","dropbox.com"},{"Opera","opera.com"},
                {"Brave Browser","brave.com"},{"Vivaldi","vivaldi.com"},
                {"Thunderbird","thunderbird.net"},{"LibreOffice","libreoffice.org"},
                {"Docker Desktop","docker.com"},{"GIMP","gimp.org"},
                {"Audacity","audacityteam.org"},{"Python","python.org"},
                {"Microsoft Photos","microsoft.com"},{"Paint.NET","getpaint.net"},
                {"Adobe Acrobat Reader","adobe.com"},{"Microsoft Visual Studio","visualstudio.microsoft.com"},
                {"Microsoft Store","microsoft.com"},{"7zip","7-zip.org"}
            };
        static string Domain(string name,string id) {
            string domain;
            if (!String.IsNullOrWhiteSpace(id)) {
                switch(id.Trim().ToLowerInvariant()) {
                    case "7zip.7zip": return "7-zip.org";
                    case "google.chrome": return "google.com";
                    case "mozilla.firefox": return "mozilla.org";
                    case "microsoft.visualstudiocode": return "code.visualstudio.com";
                    case "telegram.telegramdesktop": return "telegram.org";
                    case "9nksqgp7f2nh": return "whatsapp.com";
                }
            }
            if (!String.IsNullOrWhiteSpace(name) && known.TryGetValue(name.Trim(),out domain)) return domain;
            return null;
        }
        public static bool IsMapped(string name,string id) { return Domain(name,id)!=null; }
        static Bitmap Placeholder(string name) {
            Bitmap bitmap=new Bitmap(44,44,System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            using(Graphics g=Graphics.FromImage(bitmap)) {
                g.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);
                using(var path=Shapes.Rounded(new Rectangle(1,1,42,42),12)) {
                    using(var brush=new SolidBrush(Color.FromArgb(36,66,77))) g.FillPath(brush,path);
                }
                string letter="?";
                if (!String.IsNullOrWhiteSpace(name)) letter=name.Trim().Substring(0,1).ToUpperInvariant();
                using(var f=new Font("Segoe UI Semibold",17,FontStyle.Bold,GraphicsUnit.Pixel)) {
                    TextRenderer.DrawText(g,letter,f,new Rectangle(2,2,40,40),Color.FromArgb(167,226,225),
                        TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.NoPadding);
                }
            }
            return bitmap;
        }
        static string CachePath(string domain) {
            var root=System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"GarantStore","IconCache");
            return System.IO.Path.Combine(root,domain.Replace('.','_')+".png");
        }
        static Bitmap Decode(byte[] bytes) {
            if (bytes==null || bytes.Length<70 || bytes.Length>524288) return null;
            using(var stream=new System.IO.MemoryStream(bytes))
            using(var image=Image.FromStream(stream,true,true)) {
                if(image.Width<16 || image.Height<16 || image.Width>1024 || image.Height>1024) return null;
                var bitmap=new Bitmap(44,44,System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
                using(var graphics=Graphics.FromImage(bitmap)) {
                    graphics.Clear(Color.Transparent);
                    graphics.InterpolationMode=System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                    graphics.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                    graphics.DrawImage(image,new Rectangle(3,3,38,38));
                }
                return bitmap;
            }
        }
        static void Resolve(string key,string domain) {
            slots.Wait();
            try {
                byte[] bytes=null;
                string path=CachePath(domain);
                if (System.IO.File.Exists(path)) {
                    try { bytes=System.IO.File.ReadAllBytes(path); } catch { bytes=null; }
                }
                Bitmap icon=null;
                if (bytes!=null) { try { icon=Decode(bytes); } catch { icon=null; } }
                if (icon==null && EnableNetwork) {
                    try {
                        string endpoint="https://www.google.com/s2/favicons?domain=" + Uri.EscapeDataString(domain) + "&sz=128";
                        var req=(System.Net.HttpWebRequest)System.Net.WebRequest.Create(endpoint);
                        req.Timeout=4500; req.ReadWriteTimeout=4500; req.AllowAutoRedirect=true; req.MaximumAutomaticRedirections=3;
                        using(var response=(System.Net.HttpWebResponse)req.GetResponse()) {
                            if (response.StatusCode!=System.Net.HttpStatusCode.OK ||
                                !response.ContentType.StartsWith("image/",StringComparison.OrdinalIgnoreCase) ||
                                response.ContentLength>524288) return;
                            using(var stream=response.GetResponseStream())
                            using(var memory=new System.IO.MemoryStream()) {
                                byte[] buffer=new byte[8192]; int count;
                                while((count=stream.Read(buffer,0,buffer.Length))>0) {
                                    if (memory.Length+count>524288) return;
                                    memory.Write(buffer,0,count);
                                }
                                bytes=memory.ToArray();
                            }
                        }
                        icon=Decode(bytes);
                        if(icon!=null) {
                            try {
                                System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path));
                                string tmp=path+".tmp";
                                System.IO.File.WriteAllBytes(tmp,bytes);
                                if(System.IO.File.Exists(path)) System.IO.File.Delete(path);
                                System.IO.File.Move(tmp,path);
                            } catch { /* artwork is optional; disk errors must not affect search */ }
                        }
                    } catch { /* offline or unavailable icon; keep neutral monogram */ }
                }
                if(icon!=null) {
                    Bitmap old; if(images.TryGetValue(key,out old)) {
                        images[key]=icon;
                        System.Threading.Interlocked.Increment(ref revision);
                        // Old placeholders are intentionally retained: WinForms may still paint them.
                    }
                }
            } finally { slots.Release(); }
        }
        public static Bitmap Get(string name,string id) {
            string key=(id??"").Trim().ToLowerInvariant()+"|"+(name??"").Trim().ToLowerInvariant();
            Bitmap icon=images.GetOrAdd(key,k=>Placeholder(name));
            string domain=Domain(name,id);
            if(domain!=null && queued.TryAdd(key,1)) {
                System.Threading.Tasks.Task.Run((Action)(()=>Resolve(key,domain)));
            }
            return icon;
        }
    }
    public class GradientProgress : Control {
        private int progressValue;
        private int progressMinimum;
        private int progressMaximum=100;
        private ProgressBarStyle progressStyle=ProgressBarStyle.Continuous;
        private int marqueeSpeed;
        private int offset;
        private Timer animation;
        public Color TrackColor {get;set;}
        public Color ColorA {get;set;}
        public Color ColorB {get;set;}
        public int Minimum {get {return progressMinimum;} set {progressMinimum=value; Invalidate();} }
        public int Maximum {get {return progressMaximum;} set {progressMaximum=Math.Max(value,progressMinimum+1); Invalidate();} }
        public int Value {get {return progressValue;} set {progressValue=Math.Max(progressMinimum,Math.Min(progressMaximum,value)); Invalidate();} }
        public ProgressBarStyle Style {get {return progressStyle;} set {progressStyle=value; Reconfigure(); Invalidate();} }
        public int MarqueeAnimationSpeed {get {return marqueeSpeed;} set {marqueeSpeed=Math.Max(0,value); Reconfigure();} }
        public GradientProgress() {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint,true);
            Height=9;
            TrackColor=Color.FromArgb(25,47,62);
            ColorA=Color.FromArgb(54,239,167);
            ColorB=Color.FromArgb(21,187,206);
            animation=new Timer(); animation.Interval=42;
            animation.Tick += (sender,args)=> { offset=(offset+9)%Math.Max(1,Width+150); Invalidate(); };
        }
        void Reconfigure() {
            if (animation==null) return;
            if (progressStyle==ProgressBarStyle.Marquee && marqueeSpeed>0) {
                animation.Interval=Math.Max(22,Math.Min(150,marqueeSpeed+16));
                if (!animation.Enabled) animation.Start();
            } else { animation.Stop(); }
        }
        protected override void OnPaint(PaintEventArgs e) {
            if (Width<2 || Height<2) return;
            e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
            Rectangle r=new Rectangle(0,0,Width-1,Height-1);
            using(GraphicsPath track=Shapes.Rounded(r,Height/2)) {
                using(SolidBrush b=new SolidBrush(TrackColor)) e.Graphics.FillPath(b,track);
            }
            Rectangle fill=Rectangle.Empty;
            if (progressStyle==ProgressBarStyle.Marquee) {
                int span=Math.Max(36,Width/4);
                fill=new Rectangle(offset-span,0,span,Height-1);
            } else if (progressValue>progressMinimum) {
                double ratio=(double)(progressValue-progressMinimum)/Math.Max(1,progressMaximum-progressMinimum);
                fill=new Rectangle(0,0,(int)Math.Round(r.Width*ratio),r.Height);
            }
            if (fill.Width>1) {
                System.Drawing.Drawing2D.GraphicsState old=e.Graphics.Save();
                e.Graphics.SetClip(r);
                using(GraphicsPath shape=Shapes.Rounded(fill,Height/2)) {
                    using(LinearGradientBrush b=new LinearGradientBrush(fill,ColorA,ColorB,LinearGradientMode.Horizontal))
                        e.Graphics.FillPath(b,shape);
                }
                e.Graphics.Restore(old);
            }
        }
        protected override void Dispose(bool disposing) {
            if(disposing && animation!=null) {animation.Stop(); animation.Dispose(); animation=null;}
            base.Dispose(disposing);
        }
    }
    public class GradientButton : Button {
        bool hover;
        float transition;
        Timer hoverClock;
        public Color ColorA {get;set;}
        public Color ColorB {get;set;}
        public Color EdgeColor {get;set;}
        public int Corner {get;set;}
        public bool ShowAppIcon {get;set;}
        public GradientButton() {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor,true);
            FlatStyle=FlatStyle.Flat; FlatAppearance.BorderSize=0;
            ColorA=Color.FromArgb(40,58,78); ColorB=Color.FromArgb(31,41,60);
            EdgeColor=Color.FromArgb(75,97,116); Corner=12;
            ForeColor=Color.FromArgb(238,245,250);
            Cursor=Cursors.Hand; TabStop=true;
            hoverClock=new Timer(); hoverClock.Interval=25;
            hoverClock.Tick += (sender,args)=> {
                float target=hover ? 1f : 0f;
                transition+=(target-transition)*0.33f;
                if(Math.Abs(target-transition)<0.03f) {transition=target;hoverClock.Stop();}
                Invalidate();
            };
        }
        protected override void OnSizeChanged(EventArgs e) {
            base.OnSizeChanged(e);
            if (Width<2 || Height<2) return;
            using(GraphicsPath gp=Shapes.Rounded(new Rectangle(0,0,Width,Height),Corner)) {
                Region next=new Region(gp);
                Region previous=Region;
                Region=next;
                if(previous!=null) previous.Dispose();
            }
        }
        protected override void OnMouseEnter(EventArgs e) { hover=true;hoverClock.Start();base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover=false;hoverClock.Start();base.OnMouseLeave(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
        protected override void Dispose(bool disposing) {
            if(disposing && hoverClock!=null) { hoverClock.Stop();hoverClock.Dispose();hoverClock=null; }
            base.Dispose(disposing);
        }
        protected override void OnPaint(PaintEventArgs e) {
            e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
            Rectangle r=new Rectangle(0,0,Width-1,Height-1);
            if(r.Width<1 || r.Height<1) return;
            using(GraphicsPath gp=Shapes.Rounded(r,Corner)) {
                Color ca=Enabled ? ControlPaint.Light(ColorA,0.105f*transition) : Color.FromArgb(34,43,55);
                Color cb=Enabled ? ControlPaint.Light(ColorB,0.105f*transition) : Color.FromArgb(31,38,48);
                using(SolidBrush br=new SolidBrush(ca)) e.Graphics.FillPath(br,gp);
                using(Pen border=new Pen(Enabled ? EdgeColor : Color.FromArgb(49,58,68),1)) e.Graphics.DrawPath(border,gp);
            }
            Rectangle textArea=new Rectangle(8,3,Math.Max(1,Width-16),Math.Max(1,Height-6));
            TextFormatFlags flags=TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
                TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine;
            if(ShowAppIcon && Width>=124 && Height>=40) {
                int iconSize=Math.Min(34,Height-14);
                Bitmap icon=AppIcons.Get(Text,null);
                if(icon!=null) {
                    e.Graphics.DrawImage(icon,new Rectangle(12,(Height-iconSize)/2,iconSize,iconSize));
                    textArea=new Rectangle(19+iconSize,3,Math.Max(1,Width-iconSize-29),Math.Max(1,Height-6));
                    flags=TextFormatFlags.Left | TextFormatFlags.VerticalCenter |
                        TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine;
                }
            }
            TextRenderer.DrawText(e.Graphics,Text,Font,textArea,
                Enabled ? ForeColor : Color.FromArgb(116,126,139),flags);
            if(Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(e.Graphics,new Rectangle(4,4,Width-8,Height-8));
        }
    }
}
'@
}


function D([string]$x) {
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($x))
}

$S = @{}
$S['title'] = 'GARANT STORE  |  v0.11.0'
$S['heading'] = D 'R0FSQU5UIFNUT1JF'
$S['subtitle'] = D '0KPRgdGC0LDQvdC+0LLQutCwINC/0YDQuNC70L7QttC10L3QuNC5IFdpbmRvd3Mg0LHQtdC3INC+0YLQutGA0YvRgtC40Y8gTWljcm9zb2Z0IFN0b3Jl'
$S['query_hint'] = D '0JLQstC10LTQuNGC0LUg0L3QsNC30LLQsNC90LjQtSDQv9GA0LjQu9C+0LbQtdC90LjRjyDQuNC70Lgg0YLQvtGH0L3Ri9C5IElEINC/0LDQutC10YLQsA=='
$S['search'] = D '0J/QvtC40YHQug=='
$S['install'] = D '0KPRgdGC0LDQvdC+0LLQuNGC0Ywg0LLRi9Cx0YDQsNC90L3QvtC1'
$S['local'] = D '0KPRgdGC0LDQvdC+0LLQuNGC0YwgTVNJWC9BUFBY'
$S['doctor'] = D '0JTQuNCw0LPQvdC+0YHRgtC40LrQsA=='
$S['diagzip'] = D '0KHQvtC30LTQsNGC0YwgWklQINC00LjQsNCz0L3QvtGB0YLQuNC60Lg='
$S['cancel'] = D '0J7RgdGC0LDQvdC+0LLQuNGC0Yw='
$S['ready'] = D '0JPQvtGC0L7QstC+LiDQndCw0LnQtNC40YLQtSDQv9GA0LjQu9C+0LbQtdC90LjQtSwg0LLRi9Cx0LXRgNC40YLQtSDRgNC10LfRg9C70YzRgtCw0YIg0Lgg0LLRi9C/0L7Qu9C90LjRgtC1INC00L7RgdGC0YPQv9C90L7QtSDQtNC10LnRgdGC0LLQuNC1Lg=='
$S['running'] = D '0J7Qv9C10YDQsNGG0LjRjyDQstGL0L/QvtC70L3Rj9C10YLRgdGPLiDQn9C+0LTRgNC+0LHQvdC+0YHRgtC4INC+0YLQvtCx0YDQsNC20LDRjtGC0YHRjyDQvdC40LbQtS4='
$S['stage_starting'] = D '0JfQsNC/0YPRgdC6INC+0L/QtdGA0LDRhtC40Lg='
$S['stage_resolving'] = D '0J/RgNC+0LLQtdGA0LrQsCDQv9Cw0LrQtdGC0LA='
$S['stage_state'] = D '0J/RgNC+0LLQtdGA0LrQsCDRg9GB0YLQsNC90L7QstC70LXQvdC90L7QuSDQstC10YDRgdC40Lg='
$S['stage_services'] = D '0J/QvtC00LPQvtGC0L7QstC60LAg0YHQu9GD0LbQsSBNaWNyb3NvZnQgU3RvcmU='
$S['stage_prepare'] = D '0J/QvtC00LPQvtGC0L7QstC60LAg0YPRgdGC0LDQvdC+0LLQutC4'
$S['stage_handshake'] = D '0KHQvtC10LTQuNC90LXQvdC40LUg0YEgTWljcm9zb2Z0IFN0b3Jl'
$S['stage_authorizing'] = D '0J/QvtC70YPRh9C10L3QuNC1INGA0LDQt9GA0LXRiNC10L3QuNGPIE1pY3Jvc29mdCBTdG9yZQ=='
$S['stage_store'] = D 'TWljcm9zb2Z0IFN0b3JlINCy0YvQv9C+0LvQvdGP0LXRgiDQt9Cw0LPRgNGD0LfQutGDINC4INGD0YHRgtCw0L3QvtCy0LrRgw=='
$S['stage_downloading'] = D '0KHQutCw0YfQuNCy0LDQvdC40LU='
$S['stage_installing'] = D '0KPRgdGC0LDQvdC+0LLQutCwINC4INGA0LXQs9C40YHRgtGA0LDRhtC40Y8='
$S['stage_verifying'] = D '0J/RgNC+0LLQtdGA0LrQsCDRg9GB0YLQsNC90L7QstC60Lg='
$S['stage_completed'] = D '0JPQvtGC0L7QstC+'
$S['stage_failed'] = D '0J7Qv9C10YDQsNGG0LjRjyDQt9Cw0LLQtdGA0YjQuNC70LDRgdGMINC+0YjQuNCx0LrQvtC5'
$S['accept'] = D '0KDQsNC30YDQtdGI0LjRgtGMINC/0YDQuNC90Y/RgtC40LUg0YPRgdC70L7QstC40Lkg0LjRgdGC0L7Rh9C90LjQutCwL9C/0LDQutC10YLQsCDQtNC70Y8g0Y3RgtC+0Lkg0L7Qv9C10YDQsNGG0LjQuA=='
$S['alpha'] = D 'REVWLdCy0LXRgtC60LAgdjAuOCDigKIgUGVyZm9ybWFuY2UgY2FjaGUg4oCiIEZhc3QgcHJldmlldyDigKIgVmVyaWZpZWQgaW5zdGFsbHM='
$S['enter_query'] = D '0JLQstC10LTQuNGC0LUg0L3QsNC30LLQsNC90LjQtSDQv9GA0LjQu9C+0LbQtdC90LjRjy4='
$S['enter_id'] = D '0JLQstC10LTQuNGC0LUg0YLQvtGH0L3Ri9C5IElEINC/0LDQutC10YLQsCDQuNC3INGA0LXQt9GD0LvRjNGC0LDRgtC+0LIg0L/QvtC40YHQutCwLg=='
$S['confirm_install'] = D '0KPRgdGC0LDQvdC+0LLQuNGC0Ywg0L/QsNC60LXRgiB7MH0g0YfQtdGA0LXQtyBXaW5HZXQ/'
$S['confirm_title'] = D '0J/QvtC00YLQstC10YDQttC00LXQvdC40LU='
$S['confirm_local'] = D '0KPRgdGC0LDQvdC+0LLQuNGC0Ywg0LLRi9Cx0YDQsNC90L3Ri9C5INC/0L7QtNC/0LjRgdCw0L3QvdGL0Lkg0L/QsNC60LXRgj8NCnswfQ=='
$S['stop_confirm'] = D '0J/RgNC10YDQstCw0YLRjCDRgtC10LrRg9GJ0YPRjiDQvtC/0LXRgNCw0YbQuNGOPyDQktC+INCy0YDQtdC80Y8g0YPRgdGC0LDQvdC+0LLQutC4INGN0YLQviDQvNC+0LbQtdGCINC+0YHRgtCw0LLQuNGC0Ywg0L3QtdC30LDQstC10YDRiNGR0L3QvdC+0LUg0YHQvtGB0YLQvtGP0L3QuNC1Lg=='
$S['busy_close'] = D '0KHQvdCw0YfQsNC70LAg0LfQsNCy0LXRgNGI0LjRgtC1INC40LvQuCDQvtGB0YLQsNC90L7QstC40YLQtSDRgtC10LrRg9GJ0YPRjiDQvtC/0LXRgNCw0YbQuNGOLg=='
$S['done'] = D '0J7Qv9C10YDQsNGG0LjRjyDQt9Cw0LLQtdGA0YjQtdC90LAg0Lgg0L/RgNC+0LLQtdGA0LXQvdCwLg=='
$S['failed'] = D '0J7Qv9C10YDQsNGG0LjRjyDQt9Cw0LLQtdGA0YjQuNC70LDRgdGMINGBINC+0YjQuNCx0LrQvtC5LiDQmtC+0LQ6IHswfS4='
$S['monitor_fail'] = D '0J7RiNC40LHQutCwINC80L7QvdC40YLQvtGA0LjQvdCz0LA6IHswfQ=='
$S['start_fail'] = D '0J3QtSDRg9C00LDQu9C+0YHRjCDQt9Cw0L/Rg9GB0YLQuNGC0Ywg0L7Qv9C10YDQsNGG0LjRjjogezB9'
$S['stopped'] = D '0J7Qv9C10YDQsNGG0LjRjyDQv9GA0LjQvdGD0LTQuNGC0LXQu9GM0L3QviDQvtGB0YLQsNC90L7QstC70LXQvdCwLiDQn9GA0L7QstC10YDRjNGC0LUg0YHQvtGB0YLQvtGP0L3QuNC1INC/0LDQutC10YLQsC4='
$S['select_pkg'] = D '0J/QsNC60LXRgtGLIFdpbmRvd3M='
$S['ui_error_title'] = D '0J7RiNC40LHQutCwINC40L3RgtC10YDRhNC10LnRgdCw'
$S['ui_error_status'] = D '0J7RiNC40LHQutCwINC40L3RgtC10YDRhNC10LnRgdCwINC/0LXRgNC10YXQstCw0YfQtdC90LAuINCf0L7QtNGA0L7QsdC90L7RgdGC0Lgg0LfQsNC/0LjRgdCw0L3RiyDQsiDQttGD0YDQvdCw0Lsu'
$S['repair'] = D '0JLQvtGB0YHRgtCw0L3QvtCy0LjRgtGMIFdpbkdldA=='
$S['source_label'] = D '0JjRgdGC0L7Rh9C90LjQujo='
$S['source_auto'] = D '0JDQstGC0L4='
$S['source_store'] = D 'TWljcm9zb2Z0IFN0b3Jl'
$S['source_winget'] = D 'V2luR2V0INC60LDRgtCw0LvQvtCz'
$S['repair_confirm'] = D 'R2FyYW50IFN0b3JlINC+0LHQvdCw0YDRg9C20LjQuyDRg9GB0YLQsNGA0LXQstGI0LjQuSDQuNC70Lgg0L/QvtCy0YDQtdC20LTQtdC90L3Ri9C5IFdpbkdldC4g0KHQutCw0YfQsNGC0Ywg0YEg0L7RhNC40YbQuNCw0LvRjNC90L7Qs9C+INCw0LTRgNC10YHQsCBNaWNyb3NvZnQg0L/QvtGB0LvQtdC00L3RjtGOINC/0L7QtNC/0LjRgdCw0L3QvdGD0Y4g0LLQtdGA0YHQuNGOIEFwcCBJbnN0YWxsZXIg0Lgg0YPRgdGC0LDQvdC+0LLQuNGC0Ywg0LXQtT8g0J/RgNC40LvQvtC20LXQvdC40Y8g0L3QtSDQsdGD0LTRg9GCINGD0YHRgtCw0L3QsNCy0LvQuNCy0LDRgtGM0YHRjyDQsiDRgNCw0LzQutCw0YUg0Y3RgtC+0Lkg0L7Qv9C10YDQsNGG0LjQuC4='
$S['install_locked'] = D '0KPRgdGC0LDQvdC+0LLQutCwINC/0L4gSUQg0LLRgNC10LzQtdC90L3QviDQt9Cw0LHQu9C+0LrQuNGA0L7QstCw0L3QsCDQtNC+INC/0L7QtNGC0LLQtdGA0LbQtNC10L3QuNGPINC60L7RgNGA0LXQutGC0L3QvtC5INGA0LDQsdC+0YLRiyDQv9C+0LjRgdC60LAg0Lgg0LjRgdGC0L7Rh9C90LjQutC+0LIu'
$S['results_tab'] = D '0KDQtdC30YPQu9GM0YLQsNGC0Ys='
$S['log_tab'] = D '0JbRg9GA0L3QsNC7'
$S['col_name'] = D '0J3QsNC30LLQsNC90LjQtQ=='
$S['col_id'] = D 'SUQ='
$S['col_version'] = D '0JLQtdGA0YHQuNGP'
$S['col_source'] = D '0JjRgdGC0L7Rh9C90LjQug=='
$S['col_match'] = D '0KHQvtCy0L/QsNC00LXQvdC40LU='
$S['no_results'] = D '0J/QviDQt9Cw0L/RgNC+0YHRgyDQvdC1INC90LDQudC00LXQvdC+INC/0L7QtNGF0L7QtNGP0YnQuNGFINC/0YDQuNC70L7QttC10L3QuNC5Lg=='
$S['found_count'] = D '0J3QsNC50LTQtdC90L4g0L/RgNC40LvQvtC20LXQvdC40Lk6IHswfS4g0JLRi9Cx0LXRgNC40YLQtSDQvdGD0LbQvdC+0LUg0LjQtyDRgtCw0LHQu9C40YbRiy4='
$S['select_result'] = D '0KHQvdCw0YfQsNC70LAg0LLRi9Cx0LXRgNC40YLQtSDQv9GA0LjQu9C+0LbQtdC90LjQtSDQsiDRgtCw0LHQu9C40YbQtSDRgNC10LfRg9C70YzRgtCw0YLQvtCyLg=='
$S['confirm_selected'] = D '0KPRgdGC0LDQvdC+0LLQuNGC0Ywg0LLRi9Cx0YDQsNC90L3QvtC1INC/0YDQuNC70L7QttC10L3QuNC1Pw0KDQrQndCw0LfQstCw0L3QuNC1OiB7MH0NCklEOiB7MX0NCtCY0YHRgtC+0YfQvdC40Lo6IHsyfQ0KDQrQndCw0LbQuNC80LDRjyDCq9CU0LDCuywg0LLRiyDRgNCw0LfRgNC10YjQsNC10YLQtSBHYXJhbnQgU3RvcmUg0L/RgNC40L3Rj9GC0Ywg0YPRgdC70L7QstC40Y8g0LjRgdGC0L7Rh9C90LjQutCwINC4INGB0L7Qs9C70LDRiNC10L3QuNGPINCy0YvQsdGA0LDQvdC90L7Qs9C+INC/0LDQutC10YLQsCDRgtC+0LvRjNC60L4g0LTQu9GPINGN0YLQvtC5INC+0L/QtdGA0LDRhtC40Lgu'
$S['source_msstore_display'] = D 'TWljcm9zb2Z0IFN0b3Jl'
$S['source_winget_display'] = D 'V2luR2V0'
$S['bad_result'] = D '0JLRi9Cx0YDQsNC90L3Ri9C5INGA0LXQt9GD0LvRjNGC0LDRgiDQvdC1INGB0L7QtNC10YDQttC40YIg0LHQtdC30L7Qv9Cw0YHQvdC+0LPQviBJRCDQuNC70Lgg0L/QvtC00LTQtdGA0LbQuNCy0LDQtdC80L7Qs9C+INC40YHRgtC+0YfQvdC40LrQsC4='
$S['col_status'] = D '0KHRgtCw0YLRg9GB'
$S['status_not_installed'] = D '0J3QtSDRg9GB0YLQsNC90L7QstC70LXQvdC+'
$S['status_installed'] = D '0KPRgdGC0LDQvdC+0LLQu9C10L3Qvg=='
$S['status_update'] = D '0JTQvtGB0YLRg9C/0L3QviDQvtCx0L3QvtCy0LvQtdC90LjQtQ=='
$S['status_store_unknown'] = D '0KPRgdGC0LDQvdC+0LLQu9C10L3QviDCtyDQstC10YDRgdC40Y8gU3RvcmUg0L3QtdC40LfQstC10YHRgtC90LA='
$S['store_refresh_action'] = D '0J/RgNC+0LLQtdGA0LjRgtGMIC8g0L7QsdC90L7QstC40YLRjA=='
$S['confirm_store_refresh'] = D '0J/RgNC+0LLQtdGA0LjRgtGMINC4INC+0LHQvdC+0LLQuNGC0Ywg0L/RgNC40LvQvtC20LXQvdC40LUg0YfQtdGA0LXQtyBNaWNyb3NvZnQgU3RvcmU/DQoNCtCd0LDQt9Cy0LDQvdC40LU6IHswfQ0K0KPRgdGC0LDQvdC+0LLQu9C10L3QvjogezF9DQrQmNGB0YLQvtGH0L3QuNC6OiB7Mn0NCg0K0J3QsNC20LjQvNCw0Y8gwqvQlNCwwrssINCy0Ysg0YDQsNC30YDQtdGI0LDQtdGC0LUgR2FyYW50IFN0b3JlINC/0YDQuNC90Y/RgtGMINGD0YHQu9C+0LLQuNGPIE1pY3Jvc29mdCBTdG9yZSDQuCDQstGL0LHRgNCw0L3QvdC+0LPQviDQv9Cw0LrQtdGC0LAg0YLQvtC70YzQutC+INC00LvRjyDRjdGC0L7QuSDQvtC/0LXRgNCw0YbQuNC4LiDQndC10L7QsdGF0L7QtNC40LzRi9C1INGB0LjRgdGC0LXQvNC90YvQtSDRgdC70YPQttCx0Ysg0LHRg9C00YPRgiDQv9GA0L7QstC10YDQtdC90Ysg0LDQstGC0L7QvNCw0YLQuNGH0LXRgdC60Lgu'
$S['store_refresh_verified'] = D 'TWljcm9zb2Z0IFN0b3JlINCy0YvQv9C+0LvQvdC40Lsg0L7QsdC90L7QstC70LXQvdC40LUv0L/QtdGA0LXRg9GB0YLQsNC90L7QstC60YMg0L/QsNC60LXRgtCwLiDQo9GB0YLQsNC90L7QstC60LAg0L/QvtC00YLQstC10YDQttC00LXQvdCwLg=='
$S['status_unknown'] = D '0J3QtSDRg9C00LDQu9C+0YHRjCDQv9GA0L7QstC10YDQuNGC0Yw='
$S['status_checking'] = D '0J/RgNC+0LLQtdGA0LrQsC4uLg=='
$S['checking_status_line'] = D '0J/RgNC+0LLQtdGA0Y/RjiDRgtC+0YfQvdGL0Lkg0YHRgtCw0YLRg9GBINCy0YvQsdGA0LDQvdC90L7Qs9C+INC/0LDQutC10YLQsDogezB9'
$S['preview_status'] = D '0J3QsNC50LTQtdC90L46IHswfSDigKIg0L/QvtC40YHQuiB7MX0g0LzRgSDigKIg0L/RgNC+0LLQtdGA0Y/RjiDRgdC+0YHRgtC+0Y/QvdC40LUg0L/RgNC40LvQvtC20LXQvdC40LnigKY='
$S['final_perf'] = D '0J3QsNC50LTQtdC90L46IHswfSDigKIgezF9INC80YF7Mn0='
$S['cache_badge'] = D 'IOKAoiDQutGN0Yg='
$S['fast_badge'] = D '0JHQq9Ch0KLQoNCr0Jkg0KDQldCW0JjQnA=='
$S['install_action'] = D '0KPRgdGC0LDQvdC+0LLQuNGC0Ywg0LLRi9Cx0YDQsNC90L3QvtC1'
$S['update_action'] = D '0J7QsdC90L7QstC40YLRjCDQstGL0LHRgNCw0L3QvdC+0LU='
$S['already_installed'] = D '0JLRi9Cx0YDQsNC90L3QvtC1INC/0YDQuNC70L7QttC10L3QuNC1INGD0LbQtSDRg9GB0YLQsNC90L7QstC70LXQvdC+INC4INC+0LHQvdC+0LLQu9C10L3QuNC1INC90LUg0L3QsNC50LTQtdC90L4u'
$S['confirm_update'] = D '0J7QsdC90L7QstC40YLRjCDQstGL0LHRgNCw0L3QvdC+0LUg0L/RgNC40LvQvtC20LXQvdC40LU/DQoNCtCd0LDQt9Cy0LDQvdC40LU6IHswfQ0K0KPRgdGC0LDQvdC+0LLQu9C10L3QvjogezF9DQrQlNC+0YHRgtGD0L/QvdC+OiB7Mn0NCtCY0YHRgtC+0YfQvdC40Lo6IHszfQ0KDQrQndCw0LbQuNC80LDRjyDCq9CU0LDCuywg0LLRiyDRgNCw0LfRgNC10YjQsNC10YLQtSBHYXJhbnQgU3RvcmUg0L/RgNC40L3Rj9GC0Ywg0YPRgdC70L7QstC40Y8g0LjRgdGC0L7Rh9C90LjQutCwINC4INC/0LDQutC10YLQsCDRgtC+0LvRjNC60L4g0LTQu9GPINGN0YLQvtC5INC+0L/QtdGA0LDRhtC40Lgu'
$S['already_current_result'] = D '0J/RgNC40LvQvtC20LXQvdC40LUg0YPQttC1INGD0YHRgtCw0L3QvtCy0LvQtdC90L4g0Lgg0L7QsdC90L7QstC70LXQvdC40LUg0L3QtSDRgtGA0LXQsdGD0LXRgtGB0Y8u'
$S['repair_verified'] = D 'V2luR2V0INC4IEFwcCBJbnN0YWxsZXIg0LLQvtGB0YHRgtCw0L3QvtCy0LvQtdC90YsuINCf0YDQvtCy0LXRgNC60Lgg0L/QvtGB0LvQtSDQstC+0YHRgdGC0LDQvdC+0LLQu9C10L3QuNGPINCy0YvQv9C+0LvQvdC10L3Riy4='
$S['diagnostics_created'] = D '0JTQuNCw0LPQvdC+0YHRgtC40YfQtdGB0LrQuNC5IFpJUCDRgdC+0LfQtNCw0L0uINCf0YPRgtGMINGD0LrQsNC30LDQvSDQsiDQttGD0YDQvdCw0LvQtS4='
$S['unknown_state'] = D '0KHQvtGB0YLQvtGP0L3QuNC1INC/0YDQuNC70L7QttC10L3QuNGPINC90LUg0YPQtNCw0LvQvtGB0Ywg0L3QsNC00LXQttC90L4g0L7Qv9GA0LXQtNC10LvQuNGC0YwuINCj0YHRgtCw0L3QvtCy0LrQsCDQt9Cw0LHQu9C+0LrQuNGA0L7QstCw0L3QsC4='

$S['catalog_tab'] = (D '0JrQsNGC0LDQu9C+0LM=')
$S['catalog_title'] = (D '0JrQsNGC0LDQu9C+0LMg0L/RgNC40LvQvtC20LXQvdC40Lk=')
$S['catalog_subtitle'] = (D '0J/QvtC00LHQvtGA0LrQuCDQtNC70Y8g0LHRi9GB0YLRgNC+0LPQviDQv9C+0LjRgdC60LAuINCj0YHRgtCw0L3QvtCy0LrQsCDRgtC+0LvRjNC60L4g0L/QvtGB0LvQtSDQv9C+0LTRgtCy0LXRgNC20LTQtdC90LjRjy4=')
$S['filter_all'] = (D '0JLRgdC1')
$S['filter_installed'] = (D '0KPRgdGC0LDQvdC+0LLQu9C10L3Qvg==')
$S['filter_missing'] = (D '0J3QtSDRg9GB0YLQsNC90L7QstC70LXQvdC+')
$S['filter_updates'] = (D '0J7QsdC90L7QstC70LXQvdC40Y8=')
$S['filter_count'] = (D '0J/QvtC60LDQt9Cw0L3QvjogezB9INC40LcgezF9')
$S['filter_empty'] = (D '0JIg0Y3RgtC+0Lkg0LrQsNGC0LXQs9C+0YDQuNC4INC/0L7QutCwINC90LXRgiDQv9GA0LjQu9C+0LbQtdC90LjQuQ==')
$S['filter_hint'] = (D '0J/QvtC/0YDQvtCx0YPQudGC0LUg0LTRgNGD0LPQvtC5INGE0LjQu9GM0YLRgCDQuNC70Lgg0L3QvtCy0YvQuSDQv9C+0LjRgdC6Lg==')
$S['catalog_popular'] = (D '0J/QvtC/0YPQu9GP0YDQvdC+0LU=')
$S['catalog_chat'] = (D '0J7QsdGJ0LXQvdC40LU=')
$S['catalog_browser'] = (D '0JHRgNCw0YPQt9C10YDRiw==')
$S['catalog_work'] = (D '0KDQsNCx0L7RgtCw')
$S['catalog_media'] = (D '0KLQstC+0YDRh9C10YHRgtCy0L4=')
$S['catalog_tools'] = (D '0KHQuNGB0YLQtdC80LA=')
$S['catalog_hint'] = (D '0JLRi9Cx0LXRgNC40YLQtSDQv9GA0LjQu9C+0LbQtdC90LjQtSDQtNC70Y8g0L/QvtC40YHQutCwINC40Lcg0L7RhNC40YbQuNCw0LvRjNC90YvRhSDQuNGB0YLQvtGH0L3QuNC60L7Qsg==')
$S['catalog_section'] = (D '0JrQkNCi0JXQk9Ce0KDQmNCY')
$S['copy_id'] = (D '0JrQvtC/0LjRgNC+0LLQsNGC0YwgSUQg0L/QsNC60LXRgtCw')
$S['copy_name'] = (D '0JrQvtC/0LjRgNC+0LLQsNGC0Ywg0L3QsNC30LLQsNC90LjQtQ==')
$S['catalog_note'] = (D '0KHQvdCw0YfQsNC70LAg0L/QvtC40YHQuiDQuCDQv9GA0L7QstC10YDQutCwLCDQt9Cw0YLQtdC8INC/0L7QtNGC0LLQtdGA0LbQtNC10L3QuNC1INGD0YHRgtCw0L3QvtCy0LrQuA==')
$S['search_results_title'] = (D '0KDQtdC30YPQu9GM0YLQsNGC0Ysg0L/QvtC40YHQutCw')
$S['catalog_badge'] = (D '0J/QntCY0KHQmiDQn9CeINCa0JDQotCQ0JvQntCT0KM=')

$S['source_terms'] = D 'TWljcm9zb2Z0IFN0b3JlINGC0YDQtdCx0YPQtdGCINC/0YDQuNC90Y/RgtGMINGD0YHQu9C+0LLQuNGPINC40YHRgtC+0YfQvdC40LrQsCDQv9C10YDQtdC0INC/0LXRgNCy0YvQvCDQv9C+0LjRgdC60L7QvC4g0J/RgNC4INC/0L7QtNC60LvRjtGH0LXQvdC40LggTWljcm9zb2Z0INC/0L7Qu9GD0YfQsNC10YIg0LTQstGD0YXQsdGD0LrQstC10L3QvdGL0Lkg0LrQvtC0INGA0LXQs9C40L7QvdCwINGD0YHRgtGA0L7QudGB0YLQstCwLgoK0KPRgdC70L7QstC40Y86IGh0dHBzOi8vYWthLm1zL21pY3Jvc29mdC1zdG9yZS10ZXJtcy1vZi10cmFuc2FjdGlvbgoK0JTQsCDigJQg0L/QvtC00LrQu9GO0YfQuNGC0YwgTWljcm9zb2Z0IFN0b3JlINC4INC/0YDQvtC00L7Qu9C20LjRgtGMINC/0L7QuNGB0LouCtCd0LXRgiDigJQg0LjRgdC60LDRgtGMINGC0L7Qu9GM0LrQviDQsiDQvtCx0YvRh9C90L7QvCDQutCw0YLQsNC70L7Qs9C1IFdpbkdldC4K0J7RgtC80LXQvdCwIOKAlCDQvtGC0LzQtdC90LjRgtGMINC/0L7QuNGB0Lou'
$S['source_terms_store'] = D 'TWljcm9zb2Z0IFN0b3JlINGC0YDQtdCx0YPQtdGCINC/0YDQuNC90Y/RgtGMINGD0YHQu9C+0LLQuNGPINC40YHRgtC+0YfQvdC40LrQsCDQv9C10YDQtdC0INC/0LXRgNCy0YvQvCDQv9C+0LjRgdC60L7QvC4g0J/RgNC4INC/0L7QtNC60LvRjtGH0LXQvdC40LggTWljcm9zb2Z0INC/0L7Qu9GD0YfQsNC10YIg0LTQstGD0YXQsdGD0LrQstC10L3QvdGL0Lkg0LrQvtC0INGA0LXQs9C40L7QvdCwINGD0YHRgtGA0L7QudGB0YLQstCwLgoK0KPRgdC70L7QstC40Y86IGh0dHBzOi8vYWthLm1zL21pY3Jvc29mdC1zdG9yZS10ZXJtcy1vZi10cmFuc2FjdGlvbgoK0JTQsCDigJQg0L/QvtC00LrQu9GO0YfQuNGC0YwgTWljcm9zb2Z0IFN0b3JlINC4INC/0L7QstGC0L7RgNC40YLRjCDQv9C+0LjRgdC6LgrQndC10YIg4oCUINC/0LXRgNC10LrQu9GO0YfQuNGC0YzRgdGPINC90LAg0L7QsdGL0YfQvdGL0Lkg0LrQsNGC0LDQu9C+0LMgV2luR2V0LgrQntGC0LzQtdC90LAg4oCUINC+0YLQvNC10L3QuNGC0Ywg0L/QvtC40YHQui4='
$S['quick_label'] = D '0J/QntCf0KPQm9Cv0KDQndCe0JU='
$S['hero_kicker'] = D 'U09GVFdBUkUgTUFOQUdFTUVOVCAgLyAgV0lORE9XUyAxMCArIDEx'
$S['hero_support'] = D '0JHRi9GB0YLRgNGL0Lkg0L/QvtC40YHQuiDigKIg0L7RhNC40YbQuNCw0LvRjNC90YvQtSDQuNGB0YLQvtGH0L3QuNC60Lgg4oCiINC/0YDQvtCy0LXRgNC10L3QvdCw0Y8g0YPRgdGC0LDQvdC+0LLQutCw'
$S['footer_new'] = D 'R0FSQU5UIFNUT1JFICAvICBERVZFTE9QTUVOVCBCVUlMRCAgICAg4oCiICAgICDQn9C+0LjRgdC6ICAvICDQl9Cw0LPRgNGD0LfQutCwICAvICDQo9GB0YLQsNC90L7QstC60LAgIC8gINCU0LjQsNCz0L3QvtGB0YLQuNC60LA='
$S['help_source'] = D 'TVMgU1RPUkUgICsgIFdJTkdFVA=='
$S['retry_winget'] = D '0J/QvtC40YHQuiDQv9GA0L7QtNC+0LvQttC10L0g0YfQtdGA0LXQtyDQutCw0YLQsNC70L7QsyBXaW5HZXQg0LHQtdC3IE1pY3Jvc29mdCBTdG9yZS4='

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$core = Join-Path $base 'GarantStore.Core.ps1'
if (-not (Test-Path -LiteralPath $core -PathType Leaf)) {
    [Windows.Forms.MessageBox]::Show('GarantStore.Core.ps1 not found.', 'Garant Store', 'OK', 'Error') | Out-Null
    exit 2
}

$script:proc = $null
$script:busy = $false
$script:outFile = $null
$script:reqFile = $null
$script:lastLength = 0L
$script:resultFile = $null
$script:progressFile = $null
$script:previewFile = $null
$script:previewLoaded = $false
$script:lastProgressSignature = ''
$script:currentAction = ''
$script:suppressSelectionStatus = $false
$script:activeSearchQuery = ''
$script:activeSearchSource = ''
$script:sourceAgreementPrompted = $false
if ([string]$env:GS_GUI_SMOKE -eq '1' -and -not [string]::IsNullOrWhiteSpace($env:GS_GUI_SMOKE_MARKER)) {
    [IO.File]::WriteAllText($env:GS_GUI_SMOKE_MARKER,'SCRIPT_ENTERED',(New-Object Text.UTF8Encoding($false)))
}

# Presentation UI: one responsive layout on top of the unchanged search/install engine.
$form = New-Object Windows.Forms.Form
$form.Text = $S.title
$form.Size = New-Object Drawing.Size(1210,820)
$form.MinimumSize = New-Object Drawing.Size(940,690)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI',9.5)
$form.BackColor = [Drawing.Color]::FromArgb(16,22,31)
$form.AutoScaleMode = 'Dpi'
$form.KeyPreview = $true

$script:palette = @{
    Text = [Drawing.Color]::FromArgb(235,243,247)
    Muted = [Drawing.Color]::FromArgb(152,171,185)
    Teal = [Drawing.Color]::FromArgb(74,207,186)
    Surface = [Drawing.Color]::FromArgb(25,39,54)
    Border = [Drawing.Color]::FromArgb(45,64,79)
}

function New-GSLabel([string]$label,[int]$size,[bool]$strong,[Drawing.Color]$color) {
    $ctrl = New-Object Windows.Forms.Label
    $ctrl.Text = $label
    $style = if ($strong) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $ctrl.Font = [Drawing.Font]::new('Segoe UI',[float]$size,$style)
    $ctrl.ForeColor = $color
    $ctrl.BackColor = [Drawing.Color]::Transparent
    $ctrl.AutoEllipsis = $true
    return $ctrl
}
function New-GSSurface([Drawing.Color]$a,[Drawing.Color]$b,[int]$corner,[bool]$glow) {
    $surface = New-Object GarantUi.GradientPanel
    $surface.ColorA = $a
    $surface.ColorB = $b
    $surface.Corner = $corner
    $surface.Glow = $glow
    $surface.GlowColor = $script:palette.Teal
    $surface.BorderColor = $script:palette.Border
    return $surface
}
function New-GSButton([string]$name,[bool]$primary) {
    $btn = New-Object GarantUi.GradientButton
    $btn.Text = $name
    $btn.Font = New-Object Drawing.Font('Segoe UI',9,[Drawing.FontStyle]::Bold)
    $btn.Corner = 12
    if ($primary) {
        $btn.ColorA = [Drawing.Color]::FromArgb(74,207,186)
        $btn.ColorB = [Drawing.Color]::FromArgb(60,181,172)
        $btn.EdgeColor = [Drawing.Color]::FromArgb(94,219,198)
        $btn.ForeColor = [Drawing.Color]::FromArgb(11,38,43)
    } else {
        $btn.ColorA = [Drawing.Color]::FromArgb(33,49,65)
        $btn.ColorB = [Drawing.Color]::FromArgb(31,47,63)
        $btn.EdgeColor = [Drawing.Color]::FromArgb(54,73,87)
        $btn.ForeColor = $script:palette.Text
    }
    return $btn
}

# HERO: identity, trustworthy feature summary, no fake health results.
$hero = New-GSSurface ([Drawing.Color]::FromArgb(26,36,49)) ([Drawing.Color]::FromArgb(26,36,49)) 16 $false
$form.Controls.Add($hero)
$heroTop = New-GSLabel (D '0KPQn9Cg0JDQktCb0JXQndCY0JUg0J/QoNCY0JvQntCW0JXQndCY0K/QnNCYIC8gV0lORE9XUyAxMCArIDEx') 8 $true ([Drawing.Color]::FromArgb(145,219,235))
$hero.Controls.Add($heroTop)
$heading = New-GSLabel 'GARANT STORE' 21 $true $script:palette.Text
$hero.Controls.Add($heading)
$subtitle = New-GSLabel (D '0J/QvtC40YHQuiDQuCDRg9GB0YLQsNC90L7QstC60LAg0L/RgNC40LvQvtC20LXQvdC40Lkg0LjQtyDQvtGE0LjRhtC40LDQu9GM0L3Ri9GFINC40YHRgtC+0YfQvdC40LrQvtCy') 10 $false ([Drawing.Color]::FromArgb(192,223,229))
$hero.Controls.Add($subtitle)
$heroLine = New-GSLabel (D '0JHRi9GB0YLRgNGL0Lkg0L/QvtC40YHQuiAgIOKAoiAgINCf0YDQvtCy0LXRgNC60LAg0YPRgdGC0LDQvdC+0LLQutC4ICAg4oCiICAg0JTQuNCw0LPQvdC+0YHRgtC40LrQsA==') 9 $false ([Drawing.Color]::FromArgb(144,208,209))
$hero.Controls.Add($heroLine)

$heroSystem = New-GSSurface ([Drawing.Color]::FromArgb(33,50,61)) ([Drawing.Color]::FromArgb(33,50,61)) 12 $false
$heroSystem.BorderColor = [Drawing.Color]::FromArgb(45,71,80)
$hero.Controls.Add($heroSystem)
$systemKicker = New-GSLabel (D '0JTQntCh0KLQo9Cf0J3Qq9CVINCa0JDQotCQ0JvQntCT0Jg=') 8 $true ([Drawing.Color]::FromArgb(157,229,221))
$systemKicker.SetBounds(16,12,220,18)
$heroSystem.Controls.Add($systemKicker)
$systemValue = New-GSLabel 'Microsoft Store  +  WinGet' 10 $true $script:palette.Text
$systemValue.SetBounds(16,33,235,24)
$heroSystem.Controls.Add($systemValue)
$systemFoot = New-GSLabel (D '0KHQvtGB0YLQvtGP0L3QuNC1INC/0YDQvtCy0LXRgNGP0LXRgtGB0Y8g0L/RgNC4INC30LDQv9GA0L7RgdC1') 8 $false ([Drawing.Color]::FromArgb(157,205,218))
$systemFoot.SetBounds(16,61,244,19)
$heroSystem.Controls.Add($systemFoot)

# SEARCH: first visual priority below brand header.
$searchCard = New-GSSurface ([Drawing.Color]::FromArgb(25,35,48)) ([Drawing.Color]::FromArgb(25,35,48)) 16 $false
$form.Controls.Add($searchCard)
$searchTitle = New-GSLabel (D '0J3QsNC50YLQuCDQvdGD0LbQvdC+0LUg0L/RgNC40LvQvtC20LXQvdC40LU=') 10 $true $script:palette.Text
$searchTitle.SetBounds(20,11,480,22)
$searchCard.Controls.Add($searchTitle)
$searchHint = New-GSLabel (D '0J3QsNC30LLQsNC90LjQtSwgSUQg0LjQu9C4INC60LvRjtGH0LXQstC+0LUg0YHQu9C+0LLQvg==') 8 $false $script:palette.Muted
$searchHint.SetBounds(20,73,470,20)
$searchCard.Controls.Add($searchHint)
$script:queryFrame = New-GSSurface ([Drawing.Color]::FromArgb(32,45,61)) ([Drawing.Color]::FromArgb(32,45,61)) 12 $false
$script:queryFrame.BorderColor = [Drawing.Color]::FromArgb(51,70,86)
$searchCard.Controls.Add($script:queryFrame)
$script:queryBox = New-Object Windows.Forms.TextBox
$script:queryBox.BorderStyle = 'None'
$script:queryBox.BackColor = [Drawing.Color]::FromArgb(32,45,61)
$script:queryBox.ForeColor = [Drawing.Color]::FromArgb(239,249,255)
$script:queryBox.Font = New-Object Drawing.Font('Segoe UI',12)
$script:queryBox.SetBounds(17,12,400,28)
$script:queryFrame.Controls.Add($script:queryBox)
$sourceBox = New-Object Windows.Forms.ComboBox
$sourceBox.DropDownStyle = 'DropDownList'
$sourceBox.FlatStyle = 'Flat'
$sourceBox.BackColor = [Drawing.Color]::FromArgb(32,45,61)
$sourceBox.ForeColor = $script:palette.Text
$sourceBox.Font = New-Object Drawing.Font('Segoe UI',9.5)
[void]$sourceBox.Items.Add((D '0JDQstGC0L7QvNCw0YLQuNGH0LXRgdC60Lg='))
[void]$sourceBox.Items.Add('Microsoft Store')
[void]$sourceBox.Items.Add('WinGet')
$sourceBox.SelectedIndex = 0
$search = New-GSButton $S.search $true
$searchCard.Controls.Add($sourceBox)
$searchCard.Controls.Add($search)

# Shortcut duplicates removed: curated catalog below is the single discovery surface.

# Primary installation + secondary maintenance actions.
$actionCard = New-GSSurface ([Drawing.Color]::FromArgb(25,35,48)) ([Drawing.Color]::FromArgb(25,35,48)) 16 $false
$form.Controls.Add($actionCard)
$install = New-GSButton $S.install $true
$install.Enabled = $false
$local = New-GSButton $S.local $false
$doctor = New-GSButton $S.doctor $false
$repair = New-GSButton $S.repair $false
$diagzip = New-GSButton $S.diagzip $false
$cancel = New-GSButton $S.cancel $false
$cancel.Enabled = $false
$cancel.ColorA = [Drawing.Color]::FromArgb(81,45,66)
$cancel.ColorB = [Drawing.Color]::FromArgb(67,39,60)
$cancel.EdgeColor = [Drawing.Color]::FromArgb(114,69,91)
foreach ($ctrl in @($install,$local,$doctor,$repair,$diagzip,$cancel)) { $actionCard.Controls.Add($ctrl) }

# Secondary maintenance operations live in a single compact menu.
# The underlying tested actions remain unchanged and can also be invoked via menu.
$toolsButton = New-GSButton (D '0JjQvdGB0YLRgNGD0LzQtdC90YLRiw==') $false
$toolsButton.Font = New-Object Drawing.Font('Segoe UI',9)
$actionCard.Controls.Add($toolsButton)
$toolsMenu = New-Object Windows.Forms.ContextMenuStrip
$toolsMenu.BackColor = [Drawing.Color]::FromArgb(28,40,57)
$toolsMenu.ForeColor = $script:palette.Text
$toolsMenu.Font = New-Object Drawing.Font('Segoe UI',9.4)
$toolLocal = [Windows.Forms.ToolStripMenuItem]::new($S.local)
$toolDoctor = [Windows.Forms.ToolStripMenuItem]::new($S.doctor)
$toolRepair = [Windows.Forms.ToolStripMenuItem]::new($S.repair)
$toolZip = [Windows.Forms.ToolStripMenuItem]::new($S.diagzip)
[void]$toolsMenu.Items.Add($toolLocal)
[void]$toolsMenu.Items.Add($toolDoctor)
[void]$toolsMenu.Items.Add($toolRepair)
[void]$toolsMenu.Items.Add($toolZip)
$toolsButton.Add_Click({ $toolsMenu.Show($toolsButton,0,$toolsButton.Height) })
$toolDoctor.Add_Click({ Invoke-UiSafe { if (-not $script:busy) { Start-Core @{ Action='doctor' } } } })
$toolZip.Add_Click({ Invoke-UiSafe { if (-not $script:busy) { Start-Core @{ Action='diagnostics' } } } })
$toolRepair.Add_Click({ Invoke-UiSafe {
    if ($script:busy) { return }
    $confirm=[Windows.Forms.MessageBox]::Show($S.repair_confirm,$S.confirm_title,'YesNo','Warning')
    if ($confirm -eq 'Yes') { Start-Core @{ Action='repairwinget' } }
} })
$toolLocal.Add_Click({ Invoke-UiSafe {
    if ($script:busy) { return }
    $dlg=New-Object Windows.Forms.OpenFileDialog
    try {
        $dlg.Filter=$S.select_pkg + '|*.msix;*.appx;*.msixbundle;*.appxbundle'
        $dlg.Multiselect=$false
        if ($dlg.ShowDialog() -eq 'OK') {
            $confirm=[Windows.Forms.MessageBox]::Show(([string]::Format($S.confirm_local,$dlg.FileName)),$S.confirm_title,'YesNo','Question')
            if ($confirm -eq 'Yes') { Start-Core @{Action='local';Package=$dlg.FileName} }
        }
    } finally { $dlg.Dispose() }
} })
$local.Visible=$false
$doctor.Visible=$false
$repair.Visible=$false
$diagzip.Visible=$false

# Operation center: dynamic status and accurate progress, no fabricated percentage.
$statusCard = New-GSSurface ([Drawing.Color]::FromArgb(25,35,48)) ([Drawing.Color]::FromArgb(25,35,48)) 16 $false
$form.Controls.Add($statusCard)
$activityTitle = New-GSLabel (D '0KbQldCd0KLQoCDQntCf0JXQoNCQ0KbQmNCZ') 8 $true ([Drawing.Color]::FromArgb(121,223,216))
$activityTitle.SetBounds(21,11,500,20)
$statusCard.Controls.Add($activityTitle)
$status = New-GSLabel $S.ready 10 $true $script:palette.Text
$status.SetBounds(21,33,920,27)
$statusCard.Controls.Add($status)
$progress = New-Object GarantUi.GradientProgress
$progress.Style = 'Continuous'
$progress.MarqueeAnimationSpeed = 0
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$progress.SetBounds(21,68,900,8)
$statusCard.Controls.Add($progress)
$progressDetail = New-GSLabel (D '0J3QtdGCINCw0LrRgtC40LLQvdC+0Lkg0LfQsNCz0YDRg9C30LrQuA==') 8 $false $script:palette.Muted
$progressDetail.SetBounds(21,80,800,19)
$statusCard.Controls.Add($progressDetail)
$activityPill = New-GSSurface ([Drawing.Color]::FromArgb(27,68,74)) ([Drawing.Color]::FromArgb(26,77,77)) 11 $false
$activityPill.BorderColor = [Drawing.Color]::FromArgb(51,119,111)
$statusCard.Controls.Add($activityPill)
$activityPillLabel = New-GSLabel (D '0JPQntCi0J7QktCe') 8 $true ([Drawing.Color]::FromArgb(155,241,219))
$activityPillLabel.TextAlign = 'MiddleCenter'
$activityPill.Controls.Add($activityPillLabel)
$status.Add_TextChanged({
    if ($null -ne $activityPillLabel) {
        $activityPillLabel.Text = if ($script:busy) { (D '0JIg0KDQkNCR0J7QotCV') } else { (D '0JPQntCi0J7QktCe') }
    }
})

# RESULT CENTER: app-list and journal with high information density.
$resultsSurface = New-GSSurface ([Drawing.Color]::FromArgb(25,35,48)) ([Drawing.Color]::FromArgb(25,35,48)) 16 $false
$form.Controls.Add($resultsSurface)
$resultsHeadline = New-GSLabel (D '0JrQsNGC0LDQu9C+0LMg0L/RgNC40LvQvtC20LXQvdC40Lk=') 11 $true $script:palette.Text
$resultsSurface.Controls.Add($resultsHeadline)
$resultsCounter = New-GSLabel (D '0JLRi9Cx0LXRgNC40YLQtSDQv9GA0LjQu9C+0LbQtdC90LjQtSDQtNC70Y8g0L/QvtC40YHQutCw') 8 $false ([Drawing.Color]::FromArgb(133,183,196))
$resultsCounter.TextAlign = 'MiddleRight'
$resultsSurface.Controls.Add($resultsCounter)

$tabs = New-Object Windows.Forms.TabControl
$tabs.DrawMode = 'OwnerDrawFixed'
$tabs.ItemSize = New-Object Drawing.Size(142,32)
$tabs.SizeMode = 'Fixed'
$tabs.Font = New-Object Drawing.Font('Segoe UI',9,[Drawing.FontStyle]::Bold)
$tabs.Add_DrawItem({
    param($sender,$drawArgs)
    $rect = $drawArgs.Bounds
    if ($rect.Width -lt 2 -or $rect.Height -lt 2) { return }
    $selected = ($drawArgs.Index -eq $tabs.SelectedIndex)
    $from = if ($selected) { [Drawing.Color]::FromArgb(42,84,85) } else { [Drawing.Color]::FromArgb(27,39,53) }
    $to = $from
    $br = [Drawing.SolidBrush]::new($from)
    try { $drawArgs.Graphics.FillRectangle($br,$rect) } finally { $br.Dispose() }
    $fore = if ($selected) { $script:palette.Text } else { $script:palette.Muted }
    [Windows.Forms.TextRenderer]::DrawText($drawArgs.Graphics,$tabs.TabPages[$drawArgs.Index].Text,$form.Font,$rect,$fore,([Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [Windows.Forms.TextFormatFlags]::VerticalCenter))
})
$resultsSurface.Controls.Add($tabs)

# Client-side curated catalog: labels are suggestions only, never package IDs.
# The ordinary WinGet search and exact install-time validation remain authoritative.
$script:catalogGroups = [ordered]@{
    popular = @('WhatsApp','Telegram','ChatGPT','Google Chrome','7-Zip','VLC','Visual Studio Code','CapCut','Microsoft PowerToys')
    chat = @('WhatsApp','Telegram','Discord','Signal','Zoom','Microsoft Teams','Viber','Skype')
    browser = @('Google Chrome','Mozilla Firefox','Brave Browser','Opera','Vivaldi','Microsoft Edge')
    work = @('7-Zip','Notepad++','Visual Studio Code','LibreOffice','SumatraPDF','Microsoft PowerToys','Everything','Obsidian')
    media = @('CapCut','VLC','OBS Studio','GIMP','Krita','Blender','Audacity','HandBrake')
    tools = @('HWiNFO','CPU-Z','CrystalDiskInfo','CrystalDiskMark','Rufus','Everything','Microsoft PowerToys','7-Zip')
}
$script:catalogCategories = @(
    @{Key='popular';Name=$S.catalog_popular},
    @{Key='chat';Name=$S.catalog_chat},
    @{Key='browser';Name=$S.catalog_browser},
    @{Key='work';Name=$S.catalog_work},
    @{Key='media';Name=$S.catalog_media},
    @{Key='tools';Name=$S.catalog_tools}
)
$script:catalogButtons = @()
$script:categoryButtons = @()
$script:catalogKey = 'popular'
$catalogPage = New-Object Windows.Forms.TabPage
$catalogPage.Text = $S.catalog_tab
$catalogPage.BackColor = [Drawing.Color]::FromArgb(22,31,44)
[void]$tabs.TabPages.Add($catalogPage)
$catalogHead = New-GSLabel $S.catalog_subtitle 9 $false $script:palette.Muted
$catalogPage.Controls.Add($catalogHead)
$categoryPanel = New-Object Windows.Forms.Panel
$categoryPanel.BackColor = [Drawing.Color]::FromArgb(22,31,44)
$catalogPage.Controls.Add($categoryPanel)
$catalogFlow = New-Object Windows.Forms.FlowLayoutPanel
$catalogFlow.WrapContents = $true
$catalogFlow.FlowDirection = 'LeftToRight'
$catalogFlow.AutoScroll = $true
$catalogFlow.BackColor = [Drawing.Color]::FromArgb(22,31,44)
$catalogPage.Controls.Add($catalogFlow)
$catalogCount = New-GSLabel '' 8 $false $script:palette.Muted
$catalogCount.TextAlign = 'MiddleRight'
$catalogPage.Controls.Add($catalogCount)
$catalogTip = New-Object Windows.Forms.ToolTip
$catalogTip.AutoPopDelay = 5500
$catalogTip.InitialDelay = 250
foreach ($entry in $script:catalogCategories) {
    $categoryButton = New-GSButton ([string]$entry.Name) $false
    $categoryButton.Tag = [string]$entry.Key
    $categoryButton.Corner = 12
    $categoryButton.Font = New-Object Drawing.Font('Segoe UI',8.6,[Drawing.FontStyle]::Bold)
    $categoryPanel.Controls.Add($categoryButton)
    $script:categoryButtons += $categoryButton
}
$catalogPage.Add_Resize({
    $cw = $catalogPage.ClientSize.Width
    $ch = $catalogPage.ClientSize.Height
    $catalogHead.SetBounds(16,8,[Math]::Max(100,$cw-180),24)
    $catalogCount.SetBounds([Math]::Max(100,$cw-170),8,152,24)
    $categoryPanel.SetBounds(12,39,[Math]::Max(200,$cw-24),43)
    $catalogFlow.SetBounds(9,91,[Math]::Max(200,$cw-18),[Math]::Max(25,$ch-97))
    $catSpace = 8
    $catWidth = [Math]::Max(85,[int][Math]::Floor(($categoryPanel.ClientSize.Width-10-5*$catSpace)/6))
    $cx = 5
    foreach ($item in @($script:categoryButtons)) {
        $item.SetBounds($cx,5,$catWidth,33)
        $cx += $catWidth + $catSpace
    }
    Resize-GSCatalogTiles
})
$resultsPage = New-Object Windows.Forms.TabPage
$resultsPage.Text = $S.results_tab
$resultsPage.BackColor = [Drawing.Color]::FromArgb(22,31,44)
[void]$tabs.TabPages.Add($resultsPage)

# Results are filtered locally, without launching winget.exe again.
$script:filterMode = 'all'
$script:filterButtons = @()
$filterBar = New-Object Windows.Forms.Panel
$filterBar.BackColor = [Drawing.Color]::FromArgb(18,31,48)
$resultsPage.Controls.Add($filterBar)
$filterDescriptors = @(
    @{Key='all';Name=$S.filter_all},
    @{Key='installed';Name=$S.filter_installed},
    @{Key='missing';Name=$S.filter_missing},
    @{Key='updates';Name=$S.filter_updates}
)
foreach ($desc in $filterDescriptors) {
    $button = New-GSButton ([string]$desc.Name) $false
    $button.Tag = [string]$desc.Key
    $button.Font = New-Object Drawing.Font('Segoe UI',8.6,[Drawing.FontStyle]::Bold)
    $filterBar.Controls.Add($button)
    $script:filterButtons += $button
}
$listArea = New-Object Windows.Forms.Panel
$listArea.BackColor = [Drawing.Color]::FromArgb(16,26,42)
$resultsPage.Controls.Add($listArea)
$resultsPage.Add_Resize({
    $cw = $resultsPage.ClientSize.Width
    $ch = $resultsPage.ClientSize.Height
    $filterBar.SetBounds(0,0,[Math]::Max(10,$cw),46)
    $listArea.SetBounds(0,46,[Math]::Max(10,$cw),[Math]::Max(10,$ch-46))
    $x = 11
    foreach ($button in @($script:filterButtons)) {
        $width = if ([string]$button.Tag -eq 'all') { 94 } else { 155 }
        $button.SetBounds($x,6,$width,34)
        $x += $width+7
    }
})
$logPage = New-Object Windows.Forms.TabPage
$logPage.Text = $S.log_tab
$logPage.BackColor = [Drawing.Color]::FromArgb(22,31,44)
[void]$tabs.TabPages.Add($logPage)

$resultsGrid = New-Object GarantUi.FastGrid
$resultsGrid.Dock = 'Fill'
$resultsGrid.ReadOnly = $true
$resultsGrid.AllowUserToAddRows = $false
$resultsGrid.AllowUserToDeleteRows = $false
$resultsGrid.AllowUserToResizeRows = $false
$resultsGrid.MultiSelect = $false
$resultsGrid.SelectionMode = 'FullRowSelect'
$resultsGrid.AutoGenerateColumns = $false
$resultsGrid.RowHeadersVisible = $false
$resultsGrid.BackgroundColor = [Drawing.Color]::FromArgb(16,26,42)
$resultsGrid.BorderStyle = 'None'
$resultsGrid.CellBorderStyle = 'SingleHorizontal'
$resultsGrid.GridColor = [Drawing.Color]::FromArgb(32,49,67)
$resultsGrid.EnableHeadersVisualStyles = $false
$resultsGrid.ColumnHeadersBorderStyle = 'None'
$resultsGrid.ColumnHeadersHeightSizeMode = 'DisableResizing'
$resultsGrid.ColumnHeadersHeight = 36
$resultsGrid.ColumnHeadersDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(23,41,62)
$resultsGrid.ColumnHeadersDefaultCellStyle.ForeColor = [Drawing.Color]::FromArgb(157,190,209)
$resultsGrid.ColumnHeadersDefaultCellStyle.Font = New-Object Drawing.Font('Segoe UI',9,[Drawing.FontStyle]::Bold)
$resultsGrid.DefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(20,30,46)
$resultsGrid.DefaultCellStyle.ForeColor = [Drawing.Color]::FromArgb(232,242,250)
$resultsGrid.DefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(30,66,74)
$resultsGrid.DefaultCellStyle.SelectionForeColor = [Drawing.Color]::White
$resultsGrid.DefaultCellStyle.Font = New-Object Drawing.Font('Segoe UI',9.5)
$resultsGrid.DefaultCellStyle.Padding = New-Object Windows.Forms.Padding(8,2,6,2)
$resultsGrid.RowTemplate.Height = 56
$resultsGrid.AlternatingRowsDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(22,32,48)
$resultsGrid.AutoSizeRowsMode = 'None'

# Icon images are advisory only; exact package identity remains in row.Tag.
$logoCol = New-Object Windows.Forms.DataGridViewImageColumn
$logoCol.Name = 'Logo'
$logoCol.HeaderText = ''
$logoCol.Width = 62
$logoCol.MinimumWidth = 62
$logoCol.ReadOnly = $true
$logoCol.ImageLayout = 'Zoom'
$logoCol.DefaultCellStyle.NullValue = $null
$logoCol.DefaultCellStyle.Padding = New-Object Windows.Forms.Padding(10,5,5,5)
[void]$resultsGrid.Columns.Add($logoCol)
foreach ($col in @(
    @{Name='Name';Title=$S.col_name;Mode='Fill';Weight=190},
    @{Name='Status';Title=$S.col_status;Mode='Width';Weight=153},
    @{Name='Source';Title=$S.col_source;Mode='Width';Weight=142},
    @{Name='Version';Title=$S.col_version;Mode='Width';Weight=94},
    @{Name='Id';Title=$S.col_id;Mode='Width';Weight=210},
    @{Name='Match';Title=$S.col_match;Mode='Width';Weight=80}
)) {
    $column = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $column.HeaderText = [string]$col.Title
    $column.Name = [string]$col.Name
    if ([string]$col.Mode -eq 'Fill') {
        $column.AutoSizeMode = 'Fill'
        $column.FillWeight = [float]$col.Weight
        $column.MinimumWidth = 155
    } else { $column.Width = [int]$col.Weight }
    [void]$resultsGrid.Columns.Add($column)
}
$resultsGrid.Columns['Match'].Visible = $false
$resultsGrid.RowTemplate.Resizable = 'False'
# Downloaded images are cached on disk and never block the WinGet search path.
[GarantUi.AppIcons]::EnableNetwork = ([string]$env:GS_GUI_SMOKE -ne '1')
$script:lastIconRevision = [GarantUi.AppIcons]::Revision
$iconRefresh = New-Object Windows.Forms.Timer
$iconRefresh.Interval = 750
$iconRefresh.Add_Tick({
    $current = [GarantUi.AppIcons]::Revision
    if ($current -eq $script:lastIconRevision) { return }
    $script:lastIconRevision = $current
    foreach ($row in @($resultsGrid.Rows)) {
        if ($null -eq $row.Tag) { continue }
        $logo = [GarantUi.AppIcons]::Get([string]$row.Tag.Name,[string]$row.Tag.Id)
        if (-not [object]::ReferenceEquals($row.Cells['Logo'].Value,$logo)) {
            $row.Cells['Logo'].Value = $logo
        }
    }
    foreach ($tile in @($script:catalogButtons)) { $tile.Invalidate() }
})
$iconRefresh.Start()

$listArea.Controls.Add($resultsGrid)

# Empty states appear only when the list has no rows.
$emptySurface = New-GSSurface ([Drawing.Color]::FromArgb(18,29,47)) ([Drawing.Color]::FromArgb(17,39,51)) 15 $false
$emptySurface.Dock = 'Fill'
$emptySurface.BorderColor = [Drawing.Color]::FromArgb(28,46,61)
$listArea.Controls.Add($emptySurface)
$emptyTitle = New-GSLabel (D '0J3QsNC50LTQuNGC0LUg0YHQstC+0ZEg0L/RgNC40LvQvtC20LXQvdC40LU=') 15 $true $script:palette.Text
$emptyTitle.TextAlign = 'MiddleCenter'
$emptySurface.Controls.Add($emptyTitle)
$emptySubtitle = New-GSLabel (D '0J3QsNGH0L3QuNGC0LUg0YEg0L/QvtC40YHQutCwINC40LvQuCDQstGL0LHQtdGA0LjRgtC1INC/0L7Qv9GD0LvRj9GA0L3QvtC1INC/0YDQuNC70L7QttC10L3QuNC1INCy0YvRiNC1') 9 $false $script:palette.Muted
$emptySubtitle.TextAlign = 'MiddleCenter'
$emptySurface.Controls.Add($emptySubtitle)
$emptySurface.Add_Resize({
    $w = $emptySurface.ClientSize.Width
    $h = $emptySurface.ClientSize.Height
    $emptyTitle.SetBounds(16,[Math]::Max(18,[int]($h/2)-40),[Math]::Max(10,$w-32),34)
    $emptySubtitle.SetBounds(18,[Math]::Max(60,[int]($h/2)+2),[Math]::Max(10,$w-36),28)
})
$emptySurface.Visible = $true

$output = New-Object Windows.Forms.TextBox
$output.Multiline = $true
$output.ScrollBars = 'Both'
$output.ReadOnly = $true
$output.WordWrap = $false
$output.Font = New-Object Drawing.Font('Consolas',9)
$output.BackColor = [Drawing.Color]::FromArgb(12,22,34)
$output.ForeColor = [Drawing.Color]::FromArgb(197,222,229)
$output.Dock = 'Fill'
$logPage.Controls.Add($output)

$footer = New-GSLabel 'GARANT STORE  /  v0.11.0' 8 $false ([Drawing.Color]::FromArgb(99,139,163))
$form.Controls.Add($footer)
$footerRight = New-GSLabel (D '0J/QntCY0KHQmiAg4oCiICDQo9Ch0KLQkNCd0J7QktCa0JAgIOKAoiAg0JTQmNCQ0JPQndCe0KHQotCY0JrQkA==') 8 $true ([Drawing.Color]::FromArgb(99,177,177))
$footerRight.TextAlign = 'MiddleRight'
$form.Controls.Add($footerRight)

# Static gradient background uses the already double-buffered native GDI+ paint pipeline.
$form.Add_Paint({
    param($sender,$e)
    $w = $form.ClientSize.Width; $h = $form.ClientSize.Height
    if ($w -lt 2 -or $h -lt 2) { return }
    $rect = New-Object Drawing.Rectangle(0,0,$w,$h)
    $brush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(16,22,31))
    try { $e.Graphics.FillRectangle($brush,$rect) } finally { $brush.Dispose() }
})

function Resize-GSCatalogTiles {
    if ($null -eq $catalogFlow) { return }
    $available = [Math]::Max(250,$catalogFlow.ClientSize.Width-28)
    $columns = if ($available -ge 920) { 4 } elseif ($available -ge 610) { 3 } else { 2 }
    $tileW = [Math]::Max(132,[int][Math]::Floor(($available-12*$columns)/$columns))
    foreach ($tile in @($script:catalogButtons)) { $tile.SetBounds(0,0,$tileW,54) }
}

function Set-GSDashboardLayout {
    $m=16
    $w=[Math]::Max(700,$form.ClientSize.Width-2*$m)

    # Compact single-column workspace; prioritize the searchable content area.
    $hero.SetBounds($m,11,$w,66)
    $heroTop.Visible=$false
    $heroLine.Visible=$false
    $subtitle.Visible=$false
    $heading.SetBounds(21,10,[Math]::Max(300,$w-300),43)
    $subtitle.SetBounds(27,51,[Math]::Max(290,$w-300),24)
    $heroSystem.SetBounds($w-255,11,239,45)
    $systemKicker.Visible=$false
    $systemFoot.Visible=$false
    $systemValue.SetBounds(14,11,215,25)

    $searchCard.SetBounds($m,85,$w,62)
    $searchTitle.Visible=$false
    $searchHint.Visible=$false
    $fieldW=[Math]::Max(260,$w-329)
    $script:queryFrame.SetBounds(13,9,$fieldW,46)
    $script:queryBox.SetBounds(17,11,[Math]::Max(150,$fieldW-34),29)
    $sourceBox.SetBounds($w-301,13,159,37)
    $search.SetBounds($w-130,9,117,46)

    $actionCard.SetBounds($m,157,$w,52)
    $install.SetBounds(13,8,185,37)
    $toolsButton.SetBounds(209,8,133,37)
    $cancel.SetBounds($w-117,8,104,37)

    $statusCard.SetBounds($m,217,$w,70)
    $activityTitle.Visible=$false
    $status.SetBounds(17,9,[Math]::Max(280,$w-204),25)
    $activityPill.SetBounds($w-165,8,145,28)
    $activityPillLabel.SetBounds(2,2,140,22)
    $progress.SetBounds(17,43,[Math]::Max(300,$w-35),6)
    $progressDetail.SetBounds(17,53,[Math]::Max(300,$w-38),18)

    $lowerTop=295
    $lowerHeight=[Math]::Max(175,$form.ClientSize.Height-$lowerTop-35)
    $resultsSurface.SetBounds($m,$lowerTop,$w,$lowerHeight)
    $resultsHeadline.SetBounds(16,8,[Math]::Max(200,$w-365),26)
    $resultsCounter.SetBounds($w-355,12,333,22)
    $tabs.SetBounds(11,38,[Math]::Max(280,$w-22),[Math]::Max(120,$lowerHeight-47))
    if($null -ne $catalogPage) {
        $catalogPage.PerformLayout()
        $resultsPage.PerformLayout()
    }
    $footer.SetBounds($m,$form.ClientSize.Height-28,[Math]::Max(200,$w-245),18)
    $footerRight.SetBounds($w-220,$form.ClientSize.Height-28,238,18)
}
$form.Add_Resize({ Set-GSDashboardLayout })
Set-GSDashboardLayout

function Show-GSCatalogCategory([string]$key) {
    if (-not $script:catalogGroups.Contains($key)) { return }
    $script:catalogKey = $key
    $catalogFlow.SuspendLayout()
    try {
        foreach ($old in @($script:catalogButtons)) {
            [void]$catalogFlow.Controls.Remove($old)
            $old.Dispose()
        }
        $script:catalogButtons = @()
        $entries = @($script:catalogGroups[$key])
        foreach ($name in $entries) {
            $tile = New-GSButton $name $false
            $tile.Tag = [string]$name
            $tile.Height = 54
            $tile.Corner = 12
            $tile.ShowAppIcon = $true
            $tile.Font = New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
            $tile.Margin = New-Object Windows.Forms.Padding(5,5,5,5)
            $tile.ColorA = [Drawing.Color]::FromArgb(29,43,59)
            $tile.ColorB = [Drawing.Color]::FromArgb(28,46,61)
            $tile.EdgeColor = [Drawing.Color]::FromArgb(46,65,79)
            $tile.Add_Click({
                param($sender,$eventArgs)
                if ($script:busy) { return }
                $script:queryBox.Text = [string]$sender.Tag
                $sourceBox.SelectedIndex = 0
                $search.PerformClick()
            })
            $catalogTip.SetToolTip($tile,$S.catalog_hint)
            $catalogFlow.Controls.Add($tile)
            $script:catalogButtons += $tile
        }
        foreach ($category in @($script:categoryButtons)) {
            $active = ([string]$category.Tag -eq $key)
            $category.ColorA = if ($active) { [Drawing.Color]::FromArgb(32,122,123) } else { [Drawing.Color]::FromArgb(37,55,76) }
            $category.ColorB = if ($active) { [Drawing.Color]::FromArgb(34,93,108) } else { [Drawing.Color]::FromArgb(27,44,65) }
            $category.EdgeColor = if ($active) { [Drawing.Color]::FromArgb(70,195,167) } else { [Drawing.Color]::FromArgb(61,83,105) }
            $category.Invalidate()
        }
        $catalogCount.Text = [string]$entries.Count + ' ' + $S.catalog_badge
    } finally {
        $catalogFlow.ResumeLayout()
    }
    Resize-GSCatalogTiles
}

function Apply-GSResultFilter {
    $visibleCount = 0
    $totalCount = $resultsGrid.Rows.Count
    $script:suppressSelectionStatus = $true
    try {
        $resultsGrid.CurrentCell = $null
        $resultsGrid.ClearSelection()
        foreach ($row in @($resultsGrid.Rows)) {
            $state = if ($null -eq $row.Tag) { '' } else { [string]$row.Tag.Status }
            $show = switch ($script:filterMode) {
                'installed' { $state -in @('Installed','StoreUpdateUnknown') }
                'missing' { $state -eq 'NotInstalled' }
                'updates' { $state -in @('UpdateAvailable','StoreUpdateUnknown') }
                default { $true }
            }
            $row.Visible = [bool]$show
            if ($show) { $visibleCount++ }
        }
        if ($visibleCount -gt 0) {
            foreach ($row in @($resultsGrid.Rows)) {
                if ($row.Visible) {
                    $resultsGrid.CurrentCell = $row.Cells['Name']
                    $row.Selected = $true
                    break
                }
            }
        }
    } finally {
        $script:suppressSelectionStatus = $false
    }
    foreach ($button in @($script:filterButtons)) {
        $active = ([string]$button.Tag -eq $script:filterMode)
        $button.ColorA = if ($active) { [Drawing.Color]::FromArgb(31,109,110) } else { [Drawing.Color]::FromArgb(37,55,76) }
        $button.ColorB = if ($active) { [Drawing.Color]::FromArgb(29,87,112) } else { [Drawing.Color]::FromArgb(27,44,65) }
        $button.EdgeColor = if ($active) { [Drawing.Color]::FromArgb(73,199,175) } else { [Drawing.Color]::FromArgb(61,83,105) }
        $button.Invalidate()
    }
    $resultsCounter.Text = [string]::Format($S.filter_count,$visibleCount,$totalCount)
    $resultsGrid.Visible = ($visibleCount -gt 0)
    $emptySurface.Visible = ($visibleCount -eq 0)
    if ($totalCount -gt 0 -and $visibleCount -eq 0) {
        $emptyTitle.Text = $S.filter_empty
        $emptySubtitle.Text = $S.filter_hint
    }
    Update-InstallActionState
}

foreach ($category in @($script:categoryButtons)) {
    $category.Add_Click({ param($sender,$e) Show-GSCatalogCategory ([string]$sender.Tag) })
}
foreach ($filterButton in @($script:filterButtons)) {
    $filterButton.Add_Click({
        param($sender,$e)
        if ($script:busy) { return }
        $script:filterMode = [string]$sender.Tag
        Apply-GSResultFilter
    })
}
Show-GSCatalogCategory 'popular'
$tabs.SelectedTab = $catalogPage
$tabs.Add_SelectedIndexChanged({
    $resultsHeadline.Text = if ($tabs.SelectedTab -eq $catalogPage) { $S.catalog_title } else { $S.search_results_title }
    Set-GSDashboardLayout
})

function Append-TextSafe([string]$text) {
    if ($output.TextLength -gt 600000) {
        $output.Text = $output.Text.Substring($output.TextLength - 250000)
    }
    $output.AppendText($text)
}

function Show-UiError([System.Exception]$Exception) {
    # Unattended Windows CI must never wait forever on an error MessageBox.
    if ([string]$env:GS_GUI_SMOKE -eq '1') {
        [Console]::Error.WriteLine(('GUI smoke failed: ' + $Exception.Message))
        exit 21
    }
    try {
        $logDir = Join-Path $env:LOCALAPPDATA 'GarantStore\Logs'
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        $logPath = Join-Path $logDir ('gui-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
        $details = ('{0} [GUI-ERROR] {1}{2}{3}{2}{4}{2}' -f (Get-Date -Format o),$Exception.Message,[Environment]::NewLine,$Exception.GetType().FullName,$Exception.StackTrace)
        [IO.File]::AppendAllText($logPath,$details,(New-Object Text.UTF8Encoding($false)))
        $status.Text = $S.ui_error_status
        Append-TextSafe ($details + [Environment]::NewLine)
        [Windows.Forms.MessageBox]::Show(($S.ui_error_status + [Environment]::NewLine + $Exception.Message),$S.ui_error_title,'OK','Error') | Out-Null
    } catch {
        [Windows.Forms.MessageBox]::Show($Exception.Message,'Garant Store','OK','Error') | Out-Null
    }
}

function Invoke-UiSafe([scriptblock]$Action) {
    try {
        & $Action
    } catch {
        Show-UiError $_.Exception
    }
}

function Get-SourceDisplayName([string]$source) {
    switch ($source) {
        'msstore' { return $S.source_msstore_display }
        'winget' { return $S.source_winget_display }
        default { return $source }
    }
}

function Clear-SearchResults {
    $script:filterMode = 'all'
    $script:suppressSelectionStatus = $true
    try {
        $resultsGrid.Rows.Clear()
        $resultsGrid.Visible = $false
        $emptySurface.Visible = $true
        $emptyTitle.Text = (D '0J3QsNC50LTQuNGC0LUg0YHQstC+0ZEg0L/RgNC40LvQvtC20LXQvdC40LU=')
        $emptySubtitle.Text = (D '0J3QsNGH0L3QuNGC0LUg0YEg0L/QvtC40YHQutCwINC40LvQuCDQstGL0LHQtdGA0LjRgtC1INC/0L7Qv9GD0LvRj9GA0L3QvtC1INC/0YDQuNC70L7QttC10L3QuNC1INCy0YvRiNC1')
        $resultsCounter.Text = (D '0J7QttC40LTQsNC90LjQtSDQt9Cw0L/RgNC+0YHQsA==')
        $install.Enabled = $false
    } finally {
        $script:suppressSelectionStatus = $false
    }
}

function Get-StatusDisplayName([string]$packageStatus) {
    switch ($packageStatus) {
        'NotInstalled' { return $S.status_not_installed }
        'Installed' { return $S.status_installed }
        'UpdateAvailable' { return $S.status_update }
        'StoreUpdateUnknown' { return $S.status_store_unknown }
        'Checking' { return $S.status_checking }
        default { return $S.status_unknown }
    }
}

function Set-RowStatus([Windows.Forms.DataGridViewRow]$row,[string]$packageStatus,[string]$installedVersion,[string]$availableVersion) {
    if ($null -eq $row -or $null -eq $row.Tag) { return }

    $row.Tag.Status = $packageStatus
    $row.Tag.InstalledVersion = $installedVersion
    $row.Tag.AvailableVersion = $availableVersion
    $row.Cells['Status'].Value = Get-StatusDisplayName $packageStatus
    $resultsGrid.InvalidateCell($row.Cells['Status'])
    if ($script:filterMode -ne 'all') { Apply-GSResultFilter }
}

function Update-InstallActionState {
    if ($script:busy -or $resultsGrid.SelectedRows.Count -lt 1) {
        $install.Enabled = $false
        $install.Text = $S.install_action
        return
    }

    $package = $resultsGrid.SelectedRows[0].Tag
    if ($null -eq $package) {
        $install.Enabled = $false
        $install.Text = $S.install_action
        return
    }

    switch ([string]$package.Status) {
        'Installed' {
            $install.Enabled = $false
            $install.Text = $S.install_action
        }
        'UpdateAvailable' {
            $install.Enabled = $true
            $install.Text = $S.update_action
        }
        'StoreUpdateUnknown' {
            $install.Enabled = $true
            $install.Text = $S.store_refresh_action
        }
        'NotInstalled' {
            $install.Enabled = $true
            $install.Text = $S.install_action
        }
        default {
            $install.Enabled = $false
            $install.Text = $S.install_action
        }
    }
}

function Read-OperationResult {
    if (-not $script:resultFile -or -not (Test-Path -LiteralPath $script:resultFile -PathType Leaf)) {
        return $null
    }

    $jsonText = [IO.File]::ReadAllText($script:resultFile,[Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($jsonText)) { return $null }
    return ($jsonText | ConvertFrom-Json)
}

function Apply-OperationResultMessage([object]$operationResult) {
    if ($null -eq $operationResult) { return }

    switch ([string]$operationResult.Status) {
        'AlreadyCurrent' { $status.Text = $S.already_current_result }
        'InstalledVerified' { $status.Text = $S.done }
        'UpdateVerified' { $status.Text = $S.done }
        'StoreRefreshVerified' { $status.Text = $S.store_refresh_verified }
        'RepairVerified' { $status.Text = $S.repair_verified }
        'DiagnosticsCreated' { $status.Text = $S.diagnostics_created }
        'InstalledVerificationInconclusive' { $status.Text = [string]$operationResult.Message }
        default {
            if (-not [string]::IsNullOrWhiteSpace([string]$operationResult.Message)) {
                $status.Text = [string]$operationResult.Message
            }
        }
    }
}

function Apply-PackageActionResultToSelectedRow([object]$operationResult) {
    if ($null -eq $operationResult -or $resultsGrid.SelectedRows.Count -lt 1) { return }

    $row = $resultsGrid.SelectedRows[0]
    if ($null -eq $row.Tag) { return }

    if ([string]$operationResult.PackageId -and
        -not [string]::Equals([string]$row.Tag.Id,[string]$operationResult.PackageId,[StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    switch ([string]$operationResult.Status) {
        'AlreadyCurrent' {
            Set-RowStatus $row 'Installed' ([string]$operationResult.NewVersion) ''
        }
        'InstalledVerified' {
            Set-RowStatus $row 'Installed' ([string]$operationResult.NewVersion) ''
        }
        'UpdateVerified' {
            Set-RowStatus $row 'Installed' ([string]$operationResult.NewVersion) ''
        }
        'StoreRefreshVerified' {
            Set-RowStatus $row 'Installed' ([string]$operationResult.NewVersion) ''
        }
    }

    Update-InstallActionState
}

function Load-SearchResults {
    Clear-SearchResults

    if (-not $script:resultFile -or -not (Test-Path -LiteralPath $script:resultFile -PathType Leaf)) {
        throw 'Structured search result file was not created.'
    }

    $payload = Read-OperationResult
    if ($null -eq $payload) {
        throw 'Structured operation result file could not be read.'
    }

    if ($payload.Data -and $payload.Data.Results) {
        $items = @($payload.Data.Results)
    } else {
        $items = @($payload.Results)
    }

    $script:suppressSelectionStatus = $true
    try {
        foreach ($item in $items) {
            $source = [string]$item.Source
            $packageStatus = [string]$item.Status

            $rowIndex = $resultsGrid.Rows.Add(
                [GarantUi.AppIcons]::Get([string]$item.Name,[string]$item.Id),
                [string]$item.Name,
                (Get-StatusDisplayName $packageStatus),
                (Get-SourceDisplayName $source),
                [string]$item.Version,
                [string]$item.Id,
                [string]$item.Match
            )

            $resultsGrid.Rows[$rowIndex].Tag = [pscustomobject]@{
                Name = [string]$item.Name
                Id = [string]$item.Id
                Version = [string]$item.Version
                Source = $source
                Match = [string]$item.Match
                Status = $packageStatus
                InstalledVersion = [string]$item.InstalledVersion
                AvailableVersion = [string]$item.AvailableVersion
            }
        }

        if ($resultsGrid.Rows.Count -gt 0) {
            $resultsGrid.Visible = $true
            $emptySurface.Visible = $false
            $resultsCounter.Text = (D '0J3QsNC50LTQtdC90L46IHswfQ==') -f $resultsGrid.Rows.Count
            $resultsGrid.ClearSelection()
            $perf = $null
            if ($payload.Data -and ($payload.Data.PSObject.Properties.Name -contains 'Performance')) { $perf = $payload.Data.Performance }
            if ($null -ne $perf) {
                $cacheText = if ([bool]$perf.SearchCacheHit) { $S.cache_badge } else { '' }
                $status.Text = [string]::Format($S.final_perf,$resultsGrid.Rows.Count,[int]$perf.TotalMs,$cacheText)
            } else {
                $status.Text = [string]::Format($S.found_count,$resultsGrid.Rows.Count)
            }
        } else {
            $status.Text = $S.no_results
            $resultsGrid.Visible = $false
            $emptySurface.Visible = $true
            $emptyTitle.Text = (D '0J3QuNGH0LXQs9C+INC90LUg0L3QsNC50LTQtdC90L4=')
            $emptySubtitle.Text = (D '0JjQt9C80LXQvdC40YLQtSDQt9Cw0L/RgNC+0YEg0LjQu9C4INC/0LXRgNC10LrQu9GO0YfQuNGC0LUg0LjRgdGC0L7Rh9C90LjQug==')
            $resultsCounter.Text = (D 'MCDQv9GA0LjQu9C+0LbQtdC90LjQuQ==')
        }
    } finally {
        $script:suppressSelectionStatus = $false
    }

    Apply-GSResultFilter
    $tabs.SelectedTab = $resultsPage
}

function Load-SearchPreview {
    if ($script:previewLoaded -or -not $script:previewFile -or -not (Test-Path -LiteralPath $script:previewFile -PathType Leaf)) {
        return
    }

    try {
        $jsonText = [IO.File]::ReadAllText($script:previewFile,[Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($jsonText)) { return }
        $payload = $jsonText | ConvertFrom-Json
        $items = @($payload.Results)

        Clear-SearchResults
        $script:suppressSelectionStatus = $true
        try {
            foreach ($item in $items) {
                $rowIndex = $resultsGrid.Rows.Add(
                    [GarantUi.AppIcons]::Get([string]$item.Name,[string]$item.Id),
                    [string]$item.Name,
                    (Get-StatusDisplayName 'Checking'),
                    (Get-SourceDisplayName ([string]$item.Source)),
                    [string]$item.Version,
                    [string]$item.Id,
                    [string]$item.Match
                )
                $resultsGrid.Rows[$rowIndex].Tag = [pscustomobject]@{
                    Name=[string]$item.Name; Id=[string]$item.Id; Version=[string]$item.Version;
                    Source=[string]$item.Source; Match=[string]$item.Match; Status='Checking';
                    InstalledVersion=''; AvailableVersion=[string]$item.Version
                }
            }
        } finally {
            $script:suppressSelectionStatus = $false
        }

        if ($resultsGrid.Rows.Count -gt 0) {
            $emptySurface.Visible = $false
            $resultsGrid.Visible = $true
            $resultsCounter.Text = (D '0J3QsNC50LTQtdC90L46IHswfSDigKIg0L/RgNC+0LLQtdGA0LrQsCDRgdGC0LDRgtGD0YHQvtCy') -f $resultsGrid.Rows.Count
        }
        Apply-GSResultFilter
        $script:previewLoaded = $true
        $status.Text = [string]::Format($S.preview_status,$items.Count,[int]$payload.SearchMs)
        $tabs.SelectedTab = $resultsPage
    } catch {
        # Core may still be completing the atomic preview write. Retry on next tick.
    }
}

function Get-SelectedPackage {
    if ($resultsGrid.SelectedRows.Count -lt 1) {
        return $null
    }

    return $resultsGrid.SelectedRows[0].Tag
}

function Format-GSSize([double]$bytes) {
    if ($bytes -ge 1GB) { return (('{0:N2}' -f ($bytes / 1GB)) + ' ' + (D '0JPQkQ==')) }
    if ($bytes -ge 1MB) { return (('{0:N1}' -f ($bytes / 1MB)) + ' ' + (D '0JzQkQ==')) }
    if ($bytes -ge 1KB) { return (('{0:N0}' -f ($bytes / 1KB)) + ' ' + (D '0JrQkQ==')) }
    return (('{0:N0}' -f $bytes) + ' ' + (D '0JE='))
}

function Format-GSDuration([double]$seconds) {
    $span = [TimeSpan]::FromSeconds([Math]::Max(0,$seconds))
    if ($span.TotalHours -ge 1) {
        return ('{0:00}:{1:00}:{2:00}' -f [int]$span.TotalHours,$span.Minutes,$span.Seconds)
    }
    return ('{0:00}:{1:00}' -f $span.Minutes,$span.Seconds)
}

function Get-GSStageText([string]$stage) {
    switch ($stage) {
        'Starting' { return $S.stage_starting }
        'ResolvingPackage' { return $S.stage_resolving }
        'CheckingState' { return $S.stage_state }
        'Services' { return $S.stage_services }
        'PreparingInstall' { return $S.stage_prepare }
        'StoreHandshake' { return $S.stage_handshake }
        'Authorizing' { return $S.stage_authorizing }
        'StoreExecution' { return $S.stage_store }
        'Downloading' { return $S.stage_downloading }
        'Installing' { return $S.stage_installing }
        'Verifying' { return $S.stage_verifying }
        'Completed' { return $S.stage_completed }
        'Failed' { return $S.stage_failed }
        default { return $S.running }
    }
}

function Update-ProgressFromFile {
    if (-not $script:progressFile -or -not (Test-Path -LiteralPath $script:progressFile -PathType Leaf)) {
        return
    }

    try {
        $jsonText = [IO.File]::ReadAllText($script:progressFile,[Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($jsonText)) { return }

        $signature = $jsonText
        if ($signature -eq $script:lastProgressSignature) { return }
        $script:lastProgressSignature = $signature

        $state = $jsonText | ConvertFrom-Json
        $stageText = Get-GSStageText ([string]$state.Stage)
        $elapsedText = Format-GSDuration ([double]$state.ElapsedSeconds)

        $status.Text = $stageText

        $parts = New-Object 'System.Collections.Generic.List[string]'
        $downloaded = [double]$state.BytesDownloaded
        $total = [double]$state.BytesTotal
        $speed = [double]$state.SpeedBytesPerSecond

        if ($downloaded -gt 0 -and $total -gt 0) {
            [void]$parts.Add((Format-GSSize $downloaded) + ' / ' + (Format-GSSize $total))
        } elseif ($downloaded -gt 0) {
            [void]$parts.Add((D '0KHQutCw0YfQsNC90L4=') + ' ' + (Format-GSSize $downloaded))
        }

        if ($speed -gt 1024) {
            [void]$parts.Add(((Format-GSSize $speed) + '/s'))

            if ($total -gt $downloaded -and $speed -gt 0) {
                $eta = ($total - $downloaded) / $speed
                [void]$parts.Add(('~ ' + (Format-GSDuration $eta) + ' ' + (D '0L7RgdGC0LDQu9C+0YHRjA==')))
            }
        }

        [void]$parts.Add(((D '0L/RgNC+0YjQu9C+') + ' ' + $elapsedText))
        $progressDetail.Text = ($parts -join '  |  ')

        $hasPercent = ($null -ne $state.Percent -and -not [bool]$state.Indeterminate)
        if ($hasPercent) {
            $value = [int][Math]::Round([Math]::Min(100,[Math]::Max(0,[double]$state.Percent)))
            if ($progress.Style -ne 'Continuous') {
                $progress.MarqueeAnimationSpeed = 0
                $progress.Style = 'Continuous'
            }
            $progress.Value = $value
        } else {
            if ($progress.Style -ne 'Marquee') {
                $progress.Value = 0
                $progress.Style = 'Marquee'
            }
            $progress.MarqueeAnimationSpeed = 25
        }
    } catch {
        # The GUI may observe the JSON while Core rewrites it. Retry next tick.
    }
}

function Set-Busy([bool]$value) {
    $script:busy = $value
    $activityPillLabel.Text = if ($value) { (D '0JIg0KDQkNCR0J7QotCV') } else { (D '0JPQntCi0J7QktCe') }
    $search.Enabled = -not $value
    if ($value) {
        $install.Enabled = $false
    }
    $local.Enabled = -not $value
    $doctor.Enabled = -not $value
    $repair.Enabled = -not $value
    $diagzip.Enabled = -not $value
    $sourceBox.Enabled = -not $value
    $toolsButton.Enabled = -not $value
    foreach ($catalogButton in @($script:catalogButtons)) { $catalogButton.Enabled = -not $value }
    $resultsGrid.Enabled = (-not $value -or $script:currentAction -eq 'search')
    $cancel.Enabled = $value
    if ($value) {
        $progress.Style = 'Marquee'
        $progress.MarqueeAnimationSpeed = 25
        $progressDetail.Text = (D '0J7QttC40LTQsNC90LjQtSDRgdCy0LXQtNC10L3QuNC5INC+INC30LDQs9GA0YPQt9C60LU=')
        $status.Text = $S.running
    } else {
        $progress.MarqueeAnimationSpeed = 0
        if ($progress.Style -ne 'Continuous') {
            $progress.Style = 'Continuous'
        }
        if ($progress.Value -lt 100) { $progress.Value = 0 }
        Update-InstallActionState
    }
}

function Cleanup-Temp {
    foreach ($p in @($script:reqFile,$script:outFile,$script:previewFile)) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            try { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    if ($script:resultFile -and (Test-Path -LiteralPath $script:resultFile)) {
        try { Remove-Item -LiteralPath $script:resultFile -Force -ErrorAction SilentlyContinue } catch {}
    }
    if ($script:progressFile -and (Test-Path -LiteralPath $script:progressFile)) {
        try { Remove-Item -LiteralPath $script:progressFile -Force -ErrorAction SilentlyContinue } catch {}
    }
    $script:reqFile = $null
    $script:outFile = $null
    $script:resultFile = $null
    $script:progressFile = $null
    $script:previewFile = $null
    $script:previewLoaded = $false
    $script:lastProgressSignature = ''
    $script:currentAction = ''
}

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    if (-not $script:busy -or -not $script:proc) { return }
    try {
        if ($script:currentAction -eq 'search') { Load-SearchPreview }
        Update-ProgressFromFile

        if ($script:outFile -and (Test-Path -LiteralPath $script:outFile)) {
            $fs = [IO.File]::Open($script:outFile,'Open','Read','ReadWrite')
            try {
                if ($fs.Length -lt $script:lastLength) { $script:lastLength = 0L }
                $remaining = $fs.Length - $script:lastLength
                while ($remaining -gt 0) {
                    $count = [int][Math]::Min($remaining,32768)
                    $buf = New-Object byte[] $count
                    [void]$fs.Seek($script:lastLength,[IO.SeekOrigin]::Begin)
                    $n = $fs.Read($buf,0,$count)
                    if ($n -le 0) { break }
                    $script:lastLength += $n
                    $remaining -= $n
                    Append-TextSafe ([Text.Encoding]::UTF8.GetString($buf,0,$n))
                }
            } finally {
                $fs.Dispose()
            }
        }

        if ($script:proc.HasExited) {
            $timer.Stop()
            $code = $script:proc.ExitCode
            try { $script:proc.Dispose() } catch {}
            $script:proc = $null
            $completedAction = $script:currentAction

            $operationResult = Read-OperationResult

            if ($null -ne $operationResult -and [bool]$operationResult.Success) {
                $progress.Style = 'Continuous'
                $progress.Value = 100
                if ($completedAction -eq 'search') {
                    Load-SearchResults
                } else {
                    Apply-OperationResultMessage $operationResult
                    if ($completedAction -eq 'install') {
                                        Apply-PackageActionResultToSelectedRow $operationResult
                    }
                }
            } else {
                if ($null -ne $operationResult) {
                    $status.Text = ([string]$operationResult.Message + ' [' + [string]$operationResult.ErrorCode + ']')
                } else {
                    $status.Text = [string]::Format($S.failed,$code)
                }
                $tabs.SelectedTab = $logPage
                $progress.Style = 'Continuous'
                $progress.Value = 0
            }

            $retryRequest = $null
            if ($completedAction -eq 'search' -and $null -ne $operationResult -and
                [string]$operationResult.ErrorCode -eq 'SourceAgreementsRequired' -and
                -not $script:sourceAgreementPrompted) {
                $script:sourceAgreementPrompted = $true
                $agreementText = if ($script:activeSearchSource -eq 'msstore') { $S.source_terms_store } else { $S.source_terms }
                $choice = [Windows.Forms.MessageBox]::Show($agreementText,$S.confirm_title,'YesNoCancel','Question')
                if ($choice -eq 'Yes') {
                    $retryRequest = @{ Action='search'; Query=$script:activeSearchQuery; Source=$script:activeSearchSource; AgreementConsent=$true }
                } elseif ($choice -eq 'No') {
                    $retryRequest = @{ Action='search'; Query=$script:activeSearchQuery; Source='winget' }
                    $sourceBox.SelectedIndex = 2
                    $status.Text = $S.retry_winget
                }
            }

            Set-Busy $false
            Cleanup-Temp
            if ($null -ne $retryRequest) {
                Start-Core $retryRequest
            }
        }
    } catch {
        $timer.Stop()
        if ($script:proc) { try { $script:proc.Dispose() } catch {}; $script:proc = $null }
        Set-Busy $false
        $status.Text = [string]::Format($S.monitor_fail,$_.Exception.Message)
        Cleanup-Temp
    }
})

function Start-Core([hashtable]$request) {
    if ($script:busy) { return }
    try {
        Cleanup-Temp
        $id = [Guid]::NewGuid().ToString('N')
        $script:reqFile = Join-Path ([IO.Path]::GetTempPath()) ('GarantStore-request-' + $id + '.json')
        $script:outFile = Join-Path ([IO.Path]::GetTempPath()) ('GarantStore-output-' + $id + '.log')
        $script:resultFile = Join-Path ([IO.Path]::GetTempPath()) ('GarantStore-result-' + $id + '.json')
        $script:progressFile = Join-Path ([IO.Path]::GetTempPath()) ('GarantStore-progress-' + $id + '.json')
        $script:previewFile = Join-Path ([IO.Path]::GetTempPath()) ('GarantStore-preview-' + $id + '.json')
        $script:previewLoaded = $false
        $script:lastProgressSignature = ''
        $script:currentAction = [string]$request.Action
        $script:lastLength = 0L

        $output.Clear()

        if ($script:currentAction -eq 'search') {
            Clear-SearchResults
            $tabs.SelectedTab = $resultsPage
        } else {
            $tabs.SelectedTab = $logPage
        }

                if ($request.ContainsKey('AgreementConsent')) {
            $request['AcceptAgreements'] = [bool]$request['AgreementConsent']
        } else {
            $request['AcceptAgreements'] = $false
        }
        $request['ResultFile'] = $script:resultFile
        $request['ProgressFile'] = $script:progressFile
        $request['PreviewFile'] = $script:previewFile
        $request['OperationId'] = ('OP-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $id.Substring(0,8))
        $json = ConvertTo-Json -InputObject $request -Depth 5 -Compress
        [IO.File]::WriteAllText($script:reqFile,$json,(New-Object Text.UTF8Encoding($false)))

        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $escapedCore = '"' + $core.Replace('"','""') + '"'
        $escapedReq = '"' + $script:reqFile.Replace('"','""') + '"'
        $escapedOut = '"' + $script:outFile.Replace('"','""') + '"'
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File ' + $escapedCore + ' -RequestFile ' + $escapedReq + ' -OutputFile ' + $escapedOut
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        Set-Busy $true
        $script:proc = [Diagnostics.Process]::Start($psi)
        if (-not $script:proc) { throw 'Process start returned null.' }
        $timer.Start()
    } catch {
        Set-Busy $false
        $status.Text = [string]::Format($S.start_fail,$_.Exception.Message)
        Cleanup-Temp
    }
}

function Get-SelectedSource {
    switch ($sourceBox.SelectedIndex) {
        1 { return 'msstore' }
        2 { return 'winget' }
        default { return '' }
    }
}

$form.Add_KeyDown({
    param($sender,$e)
    if ($e.Control -and ($e.KeyCode -eq [Windows.Forms.Keys]::K -or $e.KeyCode -eq [Windows.Forms.Keys]::L)) {
        $script:queryBox.Focus()
        $script:queryBox.SelectAll()
        $e.Handled = $true
        $e.SuppressKeyPress = $true
    }
})

$script:queryBox.Add_KeyDown({
    param($sender,$eventArgs)
    if ($eventArgs.KeyCode -eq [Windows.Forms.Keys]::Enter -and -not $script:busy) {
        $eventArgs.SuppressKeyPress = $true
        $search.PerformClick()
    }
})

$search.Add_Click({
    Invoke-UiSafe {
        $q = $script:queryBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($q)) {
            [Windows.Forms.MessageBox]::Show($S.enter_query,$S.confirm_title,'OK','Information') | Out-Null
            return
        }
        $script:activeSearchQuery = $q
        $script:activeSearchSource = Get-SelectedSource
        $script:sourceAgreementPrompted = $false
        Start-Core @{ Action='search'; Query=$q; Source=$script:activeSearchSource }
    }
})

$install.Add_Click({
    Invoke-UiSafe {
        $package = Get-SelectedPackage
        if ($null -eq $package) {
            [Windows.Forms.MessageBox]::Show($S.select_result,$S.confirm_title,'OK','Information') | Out-Null
            return
        }

        $packageId = [string]$package.Id
        $packageSource = [string]$package.Source
        $packageName = [string]$package.Name
        $packageStatus = [string]$package.Status

        if ($packageId -notmatch '^[A-Za-z0-9][A-Za-z0-9._+:-]{1,199}$' -or $packageSource -notin @('msstore','winget')) {
            [Windows.Forms.MessageBox]::Show($S.bad_result,$S.confirm_title,'OK','Error') | Out-Null
            return
        }

        if ($packageStatus -eq 'Installed') {
            [Windows.Forms.MessageBox]::Show($S.already_installed,$S.confirm_title,'OK','Information') | Out-Null
            return
        }

        if ($packageStatus -eq 'StoreUpdateUnknown') {
            $msg = [string]::Format(
                $S.confirm_store_refresh,
                $packageName,
                [string]$package.InstalledVersion,
                (Get-SourceDisplayName $packageSource)
            )
        } elseif ($packageStatus -eq 'UpdateAvailable') {
            $msg = [string]::Format(
                $S.confirm_update,
                $packageName,
                [string]$package.InstalledVersion,
                [string]$package.AvailableVersion,
                (Get-SourceDisplayName $packageSource)
            )
        } else {
            $msg = [string]::Format(
                $S.confirm_selected,
                $packageName,
                $packageId,
                (Get-SourceDisplayName $packageSource)
            )
        }

        $answer = [Windows.Forms.MessageBox]::Show($msg,$S.confirm_title,'YesNo','Question')
        if ($answer -eq 'Yes') {
            Start-Core @{
                Action='install'
                Id=$packageId
                Source=$packageSource
                Name=$packageName
                KnownStatus=$packageStatus
                AvailableVersion=[string]$package.Version
                AgreementConsent=$true
            }
        }
    }
})

# Source and status are always painted as accessible rounded pills.
# The original text remains in the underlying cells for selection/copy/accessibility.
$resultsGrid.Add_CellPainting({
    param($sender,$e)
    if ($e.RowIndex -lt 0 -or $e.ColumnIndex -lt 0) { return }
    $name = $resultsGrid.Columns[$e.ColumnIndex].Name
    if ($name -ne 'Status' -and $name -ne 'Source') { return }
    $record = $resultsGrid.Rows[$e.RowIndex].Tag
    if ($null -eq $record) { return }
    $e.PaintBackground($e.ClipBounds,$true)
    $pillLabel = [string]$e.FormattedValue
    $fore = [Drawing.Color]::FromArgb(200,219,228)
    $back = [Drawing.Color]::FromArgb(40,55,70)
    if ($name -eq 'Source') {
        if ([string]$record.Source -eq 'msstore') {
            $back = [Drawing.Color]::FromArgb(29,75,86)
            $fore = [Drawing.Color]::FromArgb(118,231,230)
        } else {
            $back = [Drawing.Color]::FromArgb(49,58,90)
            $fore = [Drawing.Color]::FromArgb(178,190,255)
        }
    } else {
        switch ([string]$record.Status) {
            'Installed' { $back=[Drawing.Color]::FromArgb(28,75,62); $fore=[Drawing.Color]::FromArgb(129,239,175) }
            'UpdateAvailable' { $back=[Drawing.Color]::FromArgb(83,68,38); $fore=[Drawing.Color]::FromArgb(255,208,124) }
            'StoreUpdateUnknown' { $back=[Drawing.Color]::FromArgb(67,63,41); $fore=[Drawing.Color]::FromArgb(236,210,147) }
            'Checking' { $back=[Drawing.Color]::FromArgb(34,66,92); $fore=[Drawing.Color]::FromArgb(141,204,254) }
            'NotInstalled' { $back=[Drawing.Color]::FromArgb(44,55,68); $fore=[Drawing.Color]::FromArgb(191,207,219) }
        }
    }
    $maxW=[Math]::Max(6,$e.CellBounds.Width-18)
    $labelFont=$resultsGrid.DefaultCellStyle.Font
    $txtSize=[Windows.Forms.TextRenderer]::MeasureText($pillLabel,$labelFont)
    $pillW=[Math]::Max(36,[Math]::Min($maxW,$txtSize.Width+17))
    $pillH=26
    $rx=$e.CellBounds.X+9
    $ry=$e.CellBounds.Y+[int](($e.CellBounds.Height-$pillH)/2)
    $rect=New-Object Drawing.Rectangle($rx,$ry,$pillW,$pillH)
    $e.Graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $path=[GarantUi.Shapes]::Rounded($rect,10)
    try {
        $brush=New-Object Drawing.SolidBrush($back)
        try { $e.Graphics.FillPath($brush,$path) } finally { $brush.Dispose() }
        $drawFlags=([Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::EndEllipsis -bor [Windows.Forms.TextFormatFlags]::SingleLine)
        [Windows.Forms.TextRenderer]::DrawText($e.Graphics,$pillLabel,$labelFont,$rect,$fore,$drawFlags)
    } finally { $path.Dispose() }
    $e.Handled=$true
})

$resultsMenu = New-Object Windows.Forms.ContextMenuStrip
$copyIdItem = [Windows.Forms.ToolStripMenuItem]::new($S.copy_id)
$copyNameItem = [Windows.Forms.ToolStripMenuItem]::new($S.copy_name)
[void]$resultsMenu.Items.Add($copyIdItem)
[void]$resultsMenu.Items.Add($copyNameItem)
$copyIdItem.Add_Click({
    $selected = Get-SelectedPackage
    if ($null -ne $selected -and -not [string]::IsNullOrWhiteSpace([string]$selected.Id)) {
        [Windows.Forms.Clipboard]::SetText([string]$selected.Id)
    }
})
$copyNameItem.Add_Click({
    $selected = Get-SelectedPackage
    if ($null -ne $selected -and -not [string]::IsNullOrWhiteSpace([string]$selected.Name)) {
        [Windows.Forms.Clipboard]::SetText([string]$selected.Name)
    }
})
$resultsMenu.Add_Opening({
    $selected = Get-SelectedPackage
    $hasSelection = ($null -ne $selected)
    $copyIdItem.Enabled = $hasSelection
    $copyNameItem.Enabled = $hasSelection
})
$resultsGrid.ContextMenuStrip = $resultsMenu
$resultsGrid.Add_KeyDown({
    param($sender,$e)
    if ($e.Control -and $e.KeyCode -eq [Windows.Forms.Keys]::C -and $resultsGrid.SelectedRows.Count -gt 0) {
        $selected = Get-SelectedPackage
        if ($null -ne $selected) {
            [Windows.Forms.Clipboard]::SetText([string]$selected.Id)
            $e.Handled = $true
            $e.SuppressKeyPress = $true
        }
    }
})

$resultsGrid.Add_SelectionChanged({
    if (-not $script:busy -and -not $script:suppressSelectionStatus) {
        Update-InstallActionState
    }
})

$resultsGrid.Add_CellDoubleClick({
    param($sender,$eventArgs)
    if ($eventArgs.RowIndex -ge 0 -and -not $script:busy -and $install.Enabled) {
        $install.PerformClick()
    }
})

$repair.Add_Click({
    Invoke-UiSafe {
        $r = [Windows.Forms.MessageBox]::Show($S.repair_confirm,$S.confirm_title,'YesNo','Warning')
        if ($r -eq 'Yes') {
            Start-Core @{ Action='repairwinget' }
        }
    }
})

$doctor.Add_Click({
    Invoke-UiSafe { Start-Core @{ Action='doctor' } }
})

$diagzip.Add_Click({
    Invoke-UiSafe { Start-Core @{ Action='diagnostics' } }
})

$local.Add_Click({
    Invoke-UiSafe {
        $dlg = New-Object Windows.Forms.OpenFileDialog
        try {
            $dlg.Filter = $S.select_pkg + '|*.msix;*.appx;*.msixbundle;*.appxbundle'
            $dlg.Multiselect = $false
            if ($dlg.ShowDialog() -eq 'OK') {
                $msg = [string]::Format($S.confirm_local,$dlg.FileName)
                $r = [Windows.Forms.MessageBox]::Show($msg,$S.confirm_title,'YesNo','Question')
                if ($r -eq 'Yes') { Start-Core @{ Action='local'; Package=$dlg.FileName } }
            }
        } finally {
            $dlg.Dispose()
        }
    }
})

$cancel.Add_Click({
    Invoke-UiSafe {
        if ($script:proc -and -not $script:proc.HasExited) {
            $r = [Windows.Forms.MessageBox]::Show($S.stop_confirm,$S.confirm_title,'YesNo','Warning')
            if ($r -eq 'Yes') {
                & taskkill.exe /PID $script:proc.Id /T /F | Out-Null
                $timer.Stop()
                try { $script:proc.Dispose() } catch {}
                $script:proc = $null
                Set-Busy $false
                $status.Text = $S.stopped
                Cleanup-Temp
            }
        }
    }
})

$form.Add_FormClosing({
    param($sender,$eventArgs)
    if ($script:busy) {
        $eventArgs.Cancel = $true
        [Windows.Forms.MessageBox]::Show($S.busy_close,$S.confirm_title,'OK','Warning') | Out-Null
    }
})

$script:guiSmokeTimer = $null
$script:guiSmokeMarker = [string]$env:GS_GUI_SMOKE_MARKER
if ([string]$env:GS_GUI_SMOKE -eq '1') {
    $script:guiSmokeTimer = New-Object Windows.Forms.Timer
    $script:guiSmokeTimer.Interval = 1200
    # The Shown handler must return immediately; validation inside it
    # can deadlock the first WinForms layout/pump on headless Windows CI.
    $form.Add_Shown({ $script:guiSmokeTimer.Start() })
    $script:guiSmokeTimer.Add_Tick({
        $script:guiSmokeTimer.Stop()
        $result = 'CLOSED'
        try {
            $errors = New-Object 'System.Collections.Generic.List[string]'
            $clientW = $form.ClientSize.Width
            if ($hero.Right -gt ($clientW+1) -or $searchCard.Right -gt ($clientW+1) -or
                $resultsSurface.Right -gt ($clientW+1)) {
                [void]$errors.Add('surface-outside-window')
            }
            if ($null -ne $form.Controls.Find('quickCard', $true) -and @($form.Controls.Find('quickCard', $true)).Count -gt 0) { [void]$errors.Add('duplicate-popular-controls') }
            # Exercise wide-window layout in the real Windows smoke gate.
            $oldSize = $form.Size
            try {
                $form.Size = New-Object Drawing.Size(1650,930)
                Set-GSDashboardLayout
                if ($resultsSurface.Right -gt ($form.ClientSize.Width+1)) { [void]$errors.Add('wide-surface-overflow') }
                if ($resultsSurface.Bottom -gt $footer.Top) { [void]$errors.Add('wide-footer-overlap') }
                if ($tabs.Right -gt ($resultsSurface.ClientSize.Width+1)) { [void]$errors.Add('wide-tabs-overflow') }
            } finally {
                $form.Size = $oldSize
                Set-GSDashboardLayout
            }
            if ($resultsSurface.Bottom -gt $footer.Top) {
                [void]$errors.Add('footer-overlap')
            }
            if ($resultsGrid.Columns.Count -ne 7) {
                [void]$errors.Add('column-count')
            } else {
                if ($resultsGrid.Columns[0].Name -ne 'Logo' -or
                    $resultsGrid.Columns[1].Name -ne 'Name' -or
                    $resultsGrid.Columns[2].Name -ne 'Status' -or
                    $resultsGrid.Columns[3].Name -ne 'Source' -or
                    $resultsGrid.Columns[4].Name -ne 'Version' -or
                    $resultsGrid.Columns[5].Name -ne 'Id') {
                    [void]$errors.Add('column-order')
                }
            }
            if ($null -eq $hero.Region -or $null -eq $searchCard.Region) {
                [void]$errors.Add('rounded-region-missing')
            }
            if (@($script:catalogButtons).Count -gt 0) {
                if (-not $script:catalogButtons[0].ShowAppIcon) { [void]$errors.Add('catalog-icon-disabled') }
            }
            if (@($script:categoryButtons).Count -ne 6) { [void]$errors.Add('category-count') }
            if (@($script:filterButtons).Count -ne 4) { [void]$errors.Add('filter-count') }
            if (@($script:catalogButtons).Count -lt 8) { [void]$errors.Add('catalog-content') }
            if ($toolsButton.Right -gt ($actionCard.ClientSize.Width+1)) { [void]$errors.Add('tools-bounds') }
            if (-not [GarantUi.AppIcons]::IsMapped('WhatsApp','9NKSQGP7F2NH')) {
                [void]$errors.Add('known-logo')
            }
            if ([GarantUi.AppIcons]::IsMapped('Elcomsoft eXplorer for WhatsApp','Elcomsoft.ExplorerforWhatsApp')) {
                [void]$errors.Add('wrong-logo-match')
            }
            if ($null -eq [GarantUi.AppIcons]::Get('Unknown Sample App','vendor.unknown')) {
                [void]$errors.Add('fallback-logo')
            }
            if ($errors.Count -gt 0) { $result='FAILED_LAYOUT;' + ($errors.ToArray() -join ',') }
        } catch {
            $result = 'SMOKE_EXCEPTION;' + $_.Exception.GetType().Name + ';' + $_.Exception.Message
        }
        if (-not [string]::IsNullOrWhiteSpace($script:guiSmokeMarker)) {
            [IO.File]::WriteAllText($script:guiSmokeMarker,$result,(New-Object Text.UTF8Encoding($false)))
        }
        $form.Close()
    })
}

$form.Add_Shown({ if ([string]$env:GS_GUI_SMOKE -ne '1') { $script:queryBox.Focus() } })

if ([string]$env:GS_GUI_SMOKE -eq '1' -and -not [string]::IsNullOrWhiteSpace($script:guiSmokeMarker)) {
    [IO.File]::WriteAllText($script:guiSmokeMarker,'PRE_SHOW',(New-Object Text.UTF8Encoding($false)))
}
[void]$form.ShowDialog()

if ($null -ne $script:guiSmokeTimer) {
    try { $script:guiSmokeTimer.Dispose() } catch {}
}
try { $iconRefresh.Stop(); $iconRefresh.Dispose() } catch {}