# Garant Store Next - WPF desktop shell. PowerShell 5.1, UTF-8 with BOM.
# Interface design principles adapted from unslop by Damir Sokolovsky, CC BY 4.0: https://github.com/heydamir/unslop
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Write-GSStartupStage([string]$Stage) {
 if($env:GS_WPF_STARTUP_TRACE){
  try{[IO.File]::AppendAllText($env:GS_WPF_STARTUP_TRACE,('{0:o} {1} {2}' -f [DateTime]::UtcNow,$PID,$Stage)+[Environment]::NewLine)}catch{}
 }
}
Write-GSStartupStage 'script-entered'
# Give the window its own Windows taskbar identity instead of inheriting the
# generic PowerShell process group. The window icon itself is set from the
# Garant Store ICO below.
Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
namespace GarantStore.Next {
    public static class ShellIdentity {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
    }
}
'@ -ErrorAction Stop
[void][GarantStore.Next.ShellIdentity]::SetCurrentProcessExplicitAppUserModelID('GarantStore.Next.Desktop')
Write-GSStartupStage 'shell-identity-initialized'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
Write-GSStartupStage 'wpf-assemblies-loaded'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
function Write-GSUiFailure {
 param([string]$Component,[Exception]$Exception,[string]$OperationId='')
 try {
  $logRoot=Join-Path $env:LOCALAPPDATA 'GarantStore\Logs'
  [IO.Directory]::CreateDirectory($logRoot) | Out-Null
  $path=Join-Path $logRoot ('ui-crash-'+(Get-Date -Format 'yyyyMMdd')+'.log')
  $entry=@(
   ('[{0:o}] Component={1}; OperationId={2}' -f (Get-Date),$Component,$OperationId)
   ('Exception={0}: {1}' -f $Exception.GetType().FullName,$Exception.Message)
   ('StackTrace={0}' -f $Exception.ToString())
   ('Version={0}; SourceCommit={1}; BuildId={2}' -f [string]$script:buildInfo.AppVersion,[string]$script:buildInfo.SourceCommit,[string]$script:buildInfo.BuildId)
  ) -join [Environment]::NewLine
  [IO.File]::AppendAllText($path,$entry+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
 } catch { }
}

$script:buildInfo=[pscustomobject]@{AppVersion='0.11.0.1';SourceCommit='unavailable';BuildId='unavailable'}
$buildInfoPath=Join-Path $root 'BuildInfo.json'
if(Test-Path -LiteralPath $buildInfoPath){try{$script:buildInfo=Get-Content -LiteralPath $buildInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json}catch{Write-GSUiFailure -Component 'BuildInfo.Load' -Exception $_.Exception}}
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Garant Store" AutomationProperties.AutomationId="GarantStoreMainWindow" Width="1280" Height="820" MinWidth="1000" MinHeight="680" WindowStartupLocation="CenterScreen" FontFamily="Segoe UI" Foreground="#EEF2EE" Background="#101413" TextOptions.TextFormattingMode="Display" SnapsToDevicePixels="True">
<Window.Resources>
 <SolidColorBrush x:Key="PageBrush" Color="#111512"/><SolidColorBrush x:Key="SidebarBrush" Color="#151A16"/><SolidColorBrush x:Key="SurfaceBrush" Color="#1B211D"/><SolidColorBrush x:Key="RaisedBrush" Color="#232A25"/><SolidColorBrush x:Key="LineBrush" Color="#303832"/><SolidColorBrush x:Key="PrimaryText" Color="#EEF2EE"/><SolidColorBrush x:Key="SecondaryText" Color="#ADB7AF"/><SolidColorBrush x:Key="MutedText" Color="#89938B"/><SolidColorBrush x:Key="AccentBrush" Color="#70E2AA"/>
 <Style x:Key="ButtonStyle" TargetType="Button">
  <Setter Property="Foreground" Value="#DCE4DD"/><Setter Property="Background" Value="#232A25"/><Setter Property="BorderBrush" Value="#343C36"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="12,9"/><Setter Property="FontSize" Value="13"/><Setter Property="FontWeight" Value="Normal"/><Setter Property="HorizontalContentAlignment" Value="Center"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="shell" CornerRadius="8" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center" RecognizesAccessKey="True"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="shell" Property="Background" Value="#2A332C"/><Setter TargetName="shell" Property="BorderBrush" Value="#48534A"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="shell" Property="Background" Value="#303A32"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="shell" Property="BorderBrush" Value="#70E2AA"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="shell" Property="Opacity" Value=".42"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
 </Style>
 <Style x:Key="NavButton" TargetType="Button" BasedOn="{StaticResource ButtonStyle}"><Setter Property="ContentTemplate"><Setter.Value><DataTemplate><StackPanel Orientation="Horizontal"><Viewbox Width="16" Height="16" Margin="0,0,10,0"><Path Data="{Binding Tag, RelativeSource={RelativeSource AncestorType=Button}}" Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}" StrokeThickness="1.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/></Viewbox><TextBlock Text="{Binding}" VerticalAlignment="Center"/></StackPanel></DataTemplate></Setter.Value></Setter><Setter Property="HorizontalContentAlignment" Value="Left"/><Setter Property="Background" Value="Transparent"/><Setter Property="BorderBrush" Value="Transparent"/><Setter Property="Padding" Value="12,8"/><Setter Property="Margin" Value="0,0,0,4"/></Style>
 <Style x:Key="CategoryButton" TargetType="Button" BasedOn="{StaticResource ButtonStyle}"><Setter Property="Padding" Value="11,7"/><Setter Property="Margin" Value="0,0,8,8"/><Setter Property="FontSize" Value="12"/><Setter Property="Background" Value="#1B211D"/><Setter Property="BorderBrush" Value="#303832"/></Style>
 <Style x:Key="AccentButton" TargetType="Button" BasedOn="{StaticResource ButtonStyle}"><Setter Property="Background" Value="#70E2AA"/><Setter Property="BorderBrush" Value="#70E2AA"/><Setter Property="Foreground" Value="#142019"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Padding" Value="17,10"/><Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#A5E0B5"/><Setter Property="BorderBrush" Value="#A5E0B5"/></Trigger></Style.Triggers></Style>
 <Style TargetType="TextBox"><Setter Property="Background" Value="#1B211D"/><Setter Property="Foreground" Value="#EEF2EE"/><Setter Property="BorderBrush" Value="#343C36"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="12,8"/><Setter Property="FontSize" Value="14"/><Setter Property="CaretBrush" Value="#70E2AA"/><Setter Property="SelectionBrush" Value="#46694E"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox"><Border x:Name="field" CornerRadius="8" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"><Grid><ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/><TextBlock Text="{Binding ToolTip,RelativeSource={RelativeSource TemplatedParent}}" Foreground="#89938B" Margin="13,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"><TextBlock.Style><Style TargetType="TextBlock"><Setter Property="Visibility" Value="Collapsed"/><Style.Triggers><DataTrigger Binding="{Binding Text,RelativeSource={RelativeSource AncestorType=TextBox}}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger><DataTrigger Binding="{Binding IsKeyboardFocusWithin,RelativeSource={RelativeSource AncestorType=TextBox}}" Value="True"><Setter Property="Visibility" Value="Collapsed"/></DataTrigger></Style.Triggers></Style></TextBlock.Style></TextBlock></Grid></Border><ControlTemplate.Triggers><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="field" Property="BorderBrush" Value="#70E2AA"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="ComboBoxItem"><Setter Property="Foreground" Value="#DCE4DD"/><Setter Property="Background" Value="#1B211D"/><Setter Property="Padding" Value="11,8"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBoxItem"><Border x:Name="option" CornerRadius="6" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsHighlighted" Value="True"><Setter TargetName="option" Property="Background" Value="#2A332C"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter TargetName="option" Property="Background" Value="#303A32"/><Setter TargetName="option" Property="TextElement.Foreground" Value="#C1E7C9"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="ComboBox"><Setter Property="Background" Value="#232A25"/><Setter Property="Foreground" Value="#DCE4DD"/><Setter Property="BorderBrush" Value="#343C36"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="10,8"/><Setter Property="MaxDropDownHeight" Value="280"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox"><Grid><ToggleButton x:Name="DropDownButton" Focusable="False" ClickMode="Press" IsChecked="{Binding IsDropDownOpen,Mode=TwoWay,RelativeSource={RelativeSource TemplatedParent}}" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"><ToggleButton.Template><ControlTemplate TargetType="ToggleButton"><Border x:Name="toggleBorder" CornerRadius="8" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"><Grid><ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Left" VerticalAlignment="Center"/><Path Data="M 0 0 L 4 4 L 8 0" Stroke="#ADB7AF" StrokeThickness="1.5" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0"/></Grid></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="toggleBorder" Property="BorderBrush" Value="#48534A"/></Trigger></ControlTemplate.Triggers></ControlTemplate></ToggleButton.Template></ToggleButton><ContentPresenter IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" ContentStringFormat="{TemplateBinding SelectionBoxItemStringFormat}" Margin="10,0,30,0" VerticalAlignment="Center" HorizontalAlignment="Left"/><Popup x:Name="Popup" Placement="Bottom" AllowsTransparency="True" Focusable="False" IsOpen="{TemplateBinding IsDropDownOpen}" PopupAnimation="Fade"><Border MinWidth="{TemplateBinding ActualWidth}" MaxHeight="{TemplateBinding MaxDropDownHeight}" Background="#1B211D" BorderBrush="#343C36" BorderThickness="1" CornerRadius="8" Margin="0,4,0,0"><ScrollViewer Margin="4" CanContentScroll="True"><ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer></Border></Popup></Grid></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="ListBoxItem"><Setter Property="Background" Value="Transparent"/><Setter Property="Margin" Value="0,0,12,12"/><Setter Property="Padding" Value="0"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem"><Border x:Name="card" CornerRadius="12" Background="#1B211D" BorderThickness="1" BorderBrush="#303832" Padding="14"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="card" Property="Background" Value="#222A24"/><Setter TargetName="card" Property="BorderBrush" Value="#465149"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter TargetName="card" Property="Background" Value="#222B24"/><Setter TargetName="card" Property="BorderBrush" Value="#70E2AA"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="card" Property="BorderBrush" Value="#70E2AA"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <ItemsPanelTemplate x:Key="Wrap"><WrapPanel IsItemsHost="True"/></ItemsPanelTemplate>
 <DataTemplate x:Key="Application"><StackPanel Width="228" Height="58"><DockPanel LastChildFill="True"><Border Width="40" Height="40" CornerRadius="10" Background="#27332A" BorderBrush="#37463A" BorderThickness="1" Margin="0,0,12,0"><TextBlock Text="{Binding Initial}" FontSize="17" FontWeight="SemiBold" Foreground="#B6E4C1" VerticalAlignment="Center" HorizontalAlignment="Center"/></Border><StackPanel VerticalAlignment="Center"><TextBlock Text="{Binding Name}" FontWeight="Medium" Foreground="#EEF2EE" FontSize="14" Width="160" TextTrimming="CharacterEllipsis"/><TextBlock Text="{Binding Detail}" Foreground="#89938B" FontSize="11" Width="160" Margin="0,5,0,0" TextTrimming="CharacterEllipsis"/></StackPanel></DockPanel></StackPanel></DataTemplate>
</Window.Resources>
<Grid>
 <Grid.ColumnDefinitions><ColumnDefinition Width="248"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
 <Border Background="#151A16" BorderBrush="#2B322D" BorderThickness="0,0,1,0">
  <Grid Margin="20,24,16,20">
   <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
   <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><StackPanel>
    <StackPanel Orientation="Horizontal" Margin="5,2,0,20"><Border Width="36" Height="36" Background="#151A16" BorderBrush="#343C36" BorderThickness="1" CornerRadius="9" Margin="0,0,11,0"><Image x:Name="BrandMarkSmall" Width="32" Height="32" Stretch="Uniform"/></Border><StackPanel VerticalAlignment="Center"><TextBlock Text="Garant Store" FontSize="16" FontWeight="SemiBold"/><TextBlock Text="Программы для Windows" FontSize="11" Foreground="#89938B" Margin="0,3,0,0"/></StackPanel></StackPanel>
    <TextBlock Text="Приложения" Foreground="#89938B" FontSize="11" Margin="12,0,0,9"/>
    <Button x:Name="GoCatalog" Tag="M2,2 H8 V8 H2 Z M12,2 H18 V8 H12 Z M2,12 H8 V18 H2 Z M12,12 H18 V18 H12 Z" Content="Каталог" Style="{StaticResource NavButton}" Margin="0,0,0,4" Background="#222B24" BorderBrush="#35463A" Foreground="#C1E7C9"/>
    <Button x:Name="GoBundles" AutomationProperties.AutomationId="OpenBundles" Tag="M3,6 H17 V17 H3 Z M7,6 V3 H13 V6 M3,10 H17" Content="Наборы" Style="{StaticResource NavButton}"/>
    <Button x:Name="GoResults" Tag="M14,8 A6,6 0 1 1 2,8 A6,6 0 1 1 14,8 M12,12 L18,18" Content="Результаты поиска" Style="{StaticResource NavButton}"/>
    <Button x:Name="GoLog" Tag="M2,2 H18 V18 H2 Z M5,6 H15 M5,10 H15 M5,14 H11" Content="Журнал операций" Style="{StaticResource NavButton}" Margin="0,0,0,12"/>
    <TextBlock Text="Обслуживание" Foreground="#89938B" FontSize="11" Margin="12,0,0,9"/>
    <Button x:Name="GoDrivers" Tag="M4,4 H16 V16 H4 Z M8,8 H12 V12 H8 Z M7,1 V4 M13,1 V4 M7,16 V19 M13,16 V19" Content="Драйверы" Style="{StaticResource NavButton}"/>
    <Button x:Name="GoComponents" Tag="M2,3 H18 V17 H2 Z M10,3 V17 M2,10 H18" Content="Компоненты Windows" Style="{StaticResource NavButton}"/>
    <Button x:Name="GoSystem" Tag="M2,3 H18 V14 H2 Z M10,14 V18 M6,18 H14" Content="Моя система" AutomationProperties.AutomationId="OpenSystemInformation" Style="{StaticResource NavButton}"/>
    <Button x:Name="Doctor" Tag="M2,10 H6 L8,5 L11,15 L14,10 H18" Content="Диагностика" Style="{StaticResource NavButton}"/>
    <Button x:Name="Repair" Tag="M17,8 A7,7 0 1 0 17,13 M17,3 V8 H12" Content="Восстановить WinGet" Style="{StaticResource NavButton}"/>
    <Button x:Name="AboutButton" Tag="M18,10 A8,8 0 1 1 2,10 A8,8 0 1 1 18,10 M10,9 V14 M10,6 V6.5" Content="О нас" Style="{StaticResource NavButton}" Margin="0,16,0,0"/>
   </StackPanel></ScrollViewer>
   <Border Grid.Row="1" Margin="0,8,0,0" VerticalAlignment="Bottom" Background="#1B211D" BorderBrush="#303832" BorderThickness="1" CornerRadius="12" Padding="14"><StackPanel><TextBlock Text="Windows 10 и 11" FontWeight="Medium" FontSize="12"/><TextBlock Text="Microsoft Store · WinGet" FontSize="11" Foreground="#89938B" Margin="0,6,0,0"/></StackPanel></Border>
  </Grid>
 </Border>
 <Grid Grid.Column="1" Margin="36,28,36,24">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <DockPanel Grid.Row="0" Margin="0,0,0,12">
   <Button x:Name="Stop" AutomationProperties.AutomationId="StopOperation" DockPanel.Dock="Right" Content="Остановить" Style="{StaticResource ButtonStyle}" IsEnabled="False" VerticalAlignment="Center"/>
   <StackPanel><TextBlock x:Name="Heading" Text="Приложения" FontSize="28" FontWeight="Medium"/><TextBlock Text="Найдите и установите нужную программу" Foreground="#ADB7AF" Margin="0,6,0,0" FontSize="13"/></StackPanel>
  </DockPanel>
  <Border Grid.Row="1" Background="#1B211D" BorderBrush="#303832" BorderThickness="1" CornerRadius="12" Padding="8" Margin="0,0,0,12">
   <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="166"/><ColumnDefinition Width="104"/></Grid.ColumnDefinitions>
    <TextBox x:Name="Query" AutomationProperties.AutomationId="SearchQuery" Grid.Column="0" ToolTip="Введите название программы" Margin="0,0,8,0" BorderThickness="0" Background="Transparent"/>
    <ComboBox x:Name="Source" AutomationProperties.AutomationId="SearchSource" Grid.Column="1" Margin="0,3,8,3" SelectedIndex="0" Padding="10,8" Background="#232A25" Foreground="#DCE4DD" BorderBrush="#343C36">
     <ComboBoxItem Content="Любой источник" Tag=""/><ComboBoxItem Content="Microsoft Store" Tag="msstore"/><ComboBoxItem Content="WinGet" Tag="winget"/>
    </ComboBox>
    <Button x:Name="Search" AutomationProperties.AutomationId="SearchButton" Grid.Column="2" Content="Найти" Style="{StaticResource AccentButton}"/>
   </Grid>
  </Border>
  <Grid Grid.Row="2">
   <Grid x:Name="CatalogView"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <DockPanel Grid.Row="0" Margin="0,0,0,12"><TextBlock Text="Подборки" FontSize="18" FontWeight="Medium"/></DockPanel>
    <WrapPanel x:Name="Categories" Grid.Row="1" Margin="0,0,0,8"/>
    <ListBox x:Name="Catalog" Grid.Row="2" Background="Transparent" BorderThickness="0" ItemTemplate="{StaticResource Application}" ItemsPanel="{StaticResource Wrap}" ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
   </Grid>
   <Grid x:Name="ResultsView" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock x:Name="ResultCount" AutomationProperties.AutomationId="SearchResultCount" Text="Результаты поиска" Foreground="#ADB7AF" Margin="0,0,0,16" FontSize="12"/>
    <ListBox x:Name="Results" AutomationProperties.AutomationId="SearchResults" Grid.Row="1" Background="Transparent" BorderThickness="0" ItemTemplate="{StaticResource Application}" ItemsPanel="{StaticResource Wrap}" ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
    <DockPanel Grid.Row="2" Margin="0,14,0,0"><Button x:Name="Install" AutomationProperties.AutomationId="InstallSelected" Content="Установить выбранное" DockPanel.Dock="Right" Style="{StaticResource AccentButton}" IsEnabled="False"/><TextBlock x:Name="Selection" AutomationProperties.AutomationId="SelectionSummary" Text="Выберите приложение" VerticalAlignment="Center" Foreground="#ADB7AF" FontSize="12"/></DockPanel>
   </Grid>
   <Grid x:Name="BundlesView" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <DockPanel Grid.Row="0" Margin="0,0,0,14"><Button x:Name="BundleBack" AutomationProperties.AutomationId="BundleBack" DockPanel.Dock="Left" Content="← Наборы" Style="{StaticResource ButtonStyle}" Margin="0,0,14,0" VerticalAlignment="Center" Visibility="Collapsed"/><StackPanel><TextBlock x:Name="BundleTitle" Text="Наборы программ" FontSize="18" FontWeight="Medium"/><TextBlock x:Name="BundleSubtitle" Text="" Foreground="#89938B" FontSize="12" Margin="0,4,0,0" TextWrapping="Wrap"/></StackPanel></DockPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><StackPanel><WrapPanel x:Name="BundleCards" AutomationProperties.AutomationId="BundleCards"/><StackPanel x:Name="BundleItems" AutomationProperties.AutomationId="BundleItems" Visibility="Collapsed" Margin="4,0,0,0"/></StackPanel></ScrollViewer>
    <DockPanel Grid.Row="2" Margin="0,14,0,0"><Button x:Name="BundleInstall" AutomationProperties.AutomationId="BundleInstall" Content="Установить выбранное" DockPanel.Dock="Right" Style="{StaticResource AccentButton}" Visibility="Collapsed" IsEnabled="False"/><Button x:Name="BundleToggle" Content="Отметить всё / снять" DockPanel.Dock="Right" Style="{StaticResource ButtonStyle}" Margin="0,0,10,0" Visibility="Collapsed"/><TextBlock x:Name="BundleSummary" AutomationProperties.AutomationId="BundleSummary" Text="" VerticalAlignment="Center" Foreground="#ADB7AF" FontSize="12"/></DockPanel>
   </Grid>
   <Grid x:Name="LogView" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <TextBlock Text="Журнал операций" FontSize="18" FontWeight="Medium" Margin="0,0,0,14"/>
    <TextBox x:Name="Log" AutomationProperties.AutomationId="OperationLog" Grid.Row="1" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" FontFamily="Consolas" FontSize="12" VerticalScrollBarVisibility="Auto"/>
   </Grid>
  </Grid>
  <Border Grid.Row="3" CornerRadius="12" Background="#1B211D" BorderBrush="#303832" BorderThickness="1" Padding="14" Margin="0,18,0,0">
   <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="168"/></Grid.ColumnDefinitions>
    <StackPanel Orientation="Horizontal" VerticalAlignment="Center"><Ellipse Width="7" Height="7" Fill="#70E2AA" Margin="0,0,11,0"/><StackPanel><TextBlock x:Name="Status" AutomationProperties.AutomationId="OperationStatus" Text="Готово к работе" FontWeight="Medium" FontSize="12"/><TextBlock x:Name="Detail" AutomationProperties.AutomationId="OperationDetail" Text="Выберите приложение или воспользуйтесь поиском" FontSize="11" Foreground="#89938B" Margin="0,4,0,0"/></StackPanel></StackPanel>
    <ProgressBar x:Name="Progress" Grid.Column="1" Height="4" VerticalAlignment="Center" Foreground="#70E2AA" Background="#343C36" BorderThickness="0"/>
   </Grid>
  </Border>
 </Grid>
</Grid></Window>
'@
$reader=New-Object System.Xml.XmlNodeReader($xaml)
Write-GSStartupStage 'loading-main-xaml'
$win=[Windows.Markup.XamlReader]::Load($reader)
Write-GSStartupStage 'main-window-created'
$reader.Close()
$script:op=$null
$script:uiDispatcher=[Windows.Threading.Dispatcher]::CurrentDispatcher
$script:uiDispatcher.add_UnhandledException({param($sender,$e)
 Write-GSUiFailure -Component 'WPF.Dispatcher' -Exception $e.Exception -OperationId $(if($script:op){[string]$script:op.Id}else{''})
 $e.Handled=$true
 try{$Status.Text='Ошибка интерфейса';$Detail.Text='Подробности записаны в диагностический журнал.'}catch{}
})
foreach($name in @('GoCatalog','GoBundles','BundlesView','BundleBack','BundleTitle','BundleSubtitle','BundleCards','BundleItems','BundleInstall','BundleToggle','BundleSummary','GoResults','GoLog','GoDrivers','GoComponents','GoSystem','Doctor','Repair','AboutButton','BrandMarkSmall','Stop','Heading','Query','Source','Search','CatalogView','ResultsView','LogView','Categories','Catalog','ResultCount','Results','Install','Selection','Log','Status','Detail','Progress')) {
 Set-Variable -Scope Script -Name $name -Value $win.FindName($name)
}
$iconPath=Join-Path $root 'Assets\GarantStoreMark.ico'
$pngMarkPath=Join-Path $root 'Assets\GarantStoreMark.png'
if(Test-Path -LiteralPath $iconPath){$win.Icon=[Windows.Media.Imaging.BitmapFrame]::Create([Uri]::new($iconPath))}
if(Test-Path -LiteralPath $pngMarkPath){$BrandMarkSmall.Source=[Windows.Media.Imaging.BitmapImage]::new([Uri]::new($pngMarkPath))}
$script:donationWhatsAppUrl='https://wa.me/79287454249?text='+[Uri]::EscapeDataString('Здравствуйте. Хочу добровольно поддержать развитие Garant Store. Пришлите, пожалуйста, актуальные реквизиты.')
$script:supportWhatsAppUrl='https://wa.me/79287454249?text='+[Uri]::EscapeDataString('Здравствуйте. Вопрос по программе Garant Store.')
$script:supportMailUrl='mailto:g-garant95@mail.ru?subject='+[Uri]::EscapeDataString('Garant Store')
$script:instagramUrl='https://instagram.com/master.vu95'
$script:supportSbp='+7(928)745-42-49'
function Show-About {
 $aboutPath=Join-Path $root 'AboutWindow.xaml'
 if(-not (Test-Path -LiteralPath $aboutPath)){$Status.Text='Не найдено окно «О программе»';return}
 try{
  [xml]$aboutXaml=Get-Content -LiteralPath $aboutPath -Raw -Encoding UTF8
  $aboutReader=New-Object System.Xml.XmlNodeReader($aboutXaml)
  $about=[Windows.Markup.XamlReader]::Load($aboutReader)
  $aboutReader.Close()
  $about.Owner=$win
  $script:aboutSmokeError=$null
  if($env:GS_WPF_SMOKE -eq '1'){$about.Add_ContentRendered({try{$about.UpdateLayout();$width=[int][Math]::Ceiling($about.ActualWidth);$height=[int][Math]::Ceiling($about.ActualHeight);$bmp=New-Object Windows.Media.Imaging.RenderTargetBitmap($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bmp.Render($about);$encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp));$shot=Join-Path ([string]$env:GS_WPF_SCREENSHOT_DIR) 'garant-next-about.png';$stream=[IO.File]::Create($shot);try{$encoder.Save($stream)}finally{$stream.Dispose()}}catch{$script:aboutSmokeError=$_.Exception.Message};$about.Close()})}
  $brand=$about.FindName('BrandMark')
  $buildLabel=$about.FindName('BuildIdentity')
  if($buildLabel){
   $shortCommit=if([string]$script:buildInfo.SourceCommit -match '^[0-9a-fA-F]{8,}') {[string]$script:buildInfo.SourceCommit.Substring(0,8)}else{'local'}
   $buildLabel.Text='Garant Store · '+[string]$script:buildInfo.AppVersion+' · '+$shortCommit+' / '+[string]$script:buildInfo.BuildId
  }
  $pngPath=Join-Path $root 'Assets\GarantStoreMark.png'
  if($brand -and (Test-Path -LiteralPath $pngPath)){$brand.Source=[Windows.Media.Imaging.BitmapImage]::new([Uri]::new($pngPath))}
  $about.FindName('ContactInstagram').Add_Click({Start-Process -FilePath $script:instagramUrl})
  $about.FindName('ContactWhatsApp').Add_Click({Start-Process -FilePath $script:supportWhatsAppUrl})
  $about.FindName('ContactEmail').Add_Click({Start-Process -FilePath $script:supportMailUrl})
  $script:aboutFeedback=$about.FindName('CopyFeedback')
  $about.FindName('CopySbp').Add_Click({try{[Windows.Clipboard]::SetText($script:supportSbp);$script:aboutFeedback.Text='Номер СБП скопирован'}catch{$script:aboutFeedback.Text='Не удалось скопировать номер'}})
  [void]$about.ShowDialog()
  if($script:aboutSmokeError){throw ('About window smoke failed: '+$script:aboutSmokeError)}
 }catch{$Status.Text='Не удалось открыть окно «О программе»: '+$_.Exception.Message}
}
$AboutButton.Add_Click({Show-About})
. (Join-Path $root 'GarantStore.Drivers.ps1')
$GoDrivers.Add_Click({Show-DriverModule})
$GoComponents.Add_Click({Show-DriverModule -InitialMode 'components'})
. (Join-Path $root 'GarantStore.System.ps1')
$GoSystem.Add_Click({Show-GSSystemPage})
$script:groups=[ordered]@{
 'Популярные'=@('WhatsApp','Telegram','ChatGPT','Google Chrome','7-Zip','VLC','Visual Studio Code','CapCut','Microsoft PowerToys')
 'Общение'=@('WhatsApp','Telegram','Discord','Signal','Zoom','Microsoft Teams')
 'Браузеры'=@('Google Chrome','Mozilla Firefox','Brave Browser','Opera','Microsoft Edge')
 'Работа'=@('7-Zip','Notepad++','Visual Studio Code','LibreOffice','Everything')
 'Творчество'=@('CapCut','VLC','OBS Studio','GIMP','Blender')
 'Система'=@('CPU-Z','HWiNFO','CrystalDiskInfo','Rufus','PowerToys')
}
# Exact package identities for catalog cards, checked against microsoft/winget-pkgs
# (and the Store ID used by the Store regression tests). A card with a known
# identity opens its install action immediately instead of running a 10-17 s
# fuzzy search; the install pipeline itself still verifies the package and its
# installed state before changing anything. Names without an entry fall back to search.
$script:catalogPackages=@{
 'WhatsApp'=@{Id='9NKSQGP7F2NH';Source='msstore'}
 'Telegram'=@{Id='Telegram.TelegramDesktop';Source='winget'}
 'Google Chrome'=@{Id='Google.Chrome';Source='winget'}
 '7-Zip'=@{Id='7zip.7zip';Source='winget'}
 'VLC'=@{Id='VideoLAN.VLC';Source='winget'}
 'Visual Studio Code'=@{Id='Microsoft.VisualStudioCode';Source='winget'}
 'CapCut'=@{Id='ByteDance.CapCut';Source='winget'}
 'Microsoft PowerToys'=@{Id='Microsoft.PowerToys';Source='winget'}
 'PowerToys'=@{Id='Microsoft.PowerToys';Source='winget'}
 'Discord'=@{Id='Discord.Discord';Source='winget'}
 'Signal'=@{Id='OpenWhisperSystems.Signal';Source='winget'}
 'Zoom'=@{Id='Zoom.Zoom';Source='winget'}
 'Microsoft Teams'=@{Id='Microsoft.Teams';Source='winget'}
 'Mozilla Firefox'=@{Id='Mozilla.Firefox';Source='winget'}
 'Brave Browser'=@{Id='Brave.Brave';Source='winget'}
 'Opera'=@{Id='Opera.Opera';Source='winget'}
 'Microsoft Edge'=@{Id='Microsoft.Edge';Source='winget'}
 'Notepad++'=@{Id='Notepad++.Notepad++';Source='winget'}
 'LibreOffice'=@{Id='TheDocumentFoundation.LibreOffice';Source='winget'}
 'Everything'=@{Id='voidtools.Everything';Source='winget'}
 'OBS Studio'=@{Id='OBSProject.OBSStudio';Source='winget'}
 'GIMP'=@{Id='GIMP.GIMP.3';Source='winget'}
 'Blender'=@{Id='BlenderFoundation.Blender';Source='winget'}
 'CPU-Z'=@{Id='CPUID.CPU-Z';Source='winget'}
 'HWiNFO'=@{Id='REALiX.HWiNFO';Source='winget'}
 'CrystalDiskInfo'=@{Id='CrystalDewWorld.CrystalDiskInfo';Source='winget'}
 'Rufus'=@{Id='Rufus.Rufus';Source='winget'}
}
function App([string]$name,[string]$id,[string]$source,[string]$status,[string]$version,[string]$installedVersion='',[string]$availableVersion=''){
 $detail=switch($status){
  'Checking'{'Проверяем статус...'}
  'NotInstalled'{'Не установлено'}
  'Installed'{'Установлено · актуально'}
  'UpdateAvailable'{'Доступно обновление'}
  'StoreUpdateUnknown'{'Установлено · обновление не проверено'}
  'Unknown'{'Не удалось проверить статус'}
  'Catalog'{'Нажмите, чтобы установить'}
  default{if($id){$id}else{'Нажмите для поиска'}}
 }
 [pscustomobject]@{Name=$name;Id=$id;Source=$source;Status=$status;Version=$version;InstalledVersion=$installedVersion;AvailableVersion=$availableVersion;Initial=$name.Substring(0,1).ToUpperInvariant();Detail=$detail}
}
function Page([string]$tab){
 $CatalogView.Visibility=if($tab -eq 'catalog'){'Visible'}else{'Collapsed'}
 $ResultsView.Visibility=if($tab -eq 'results'){'Visible'}else{'Collapsed'}
 $LogView.Visibility=if($tab -eq 'log'){'Visible'}else{'Collapsed'}
 $BundlesView.Visibility=if($tab -eq 'bundles'){'Visible'}else{'Collapsed'}
 $Heading.Text=switch($tab){'results'{'Результаты поиска'}'log'{'Журнал операций'}'bundles'{'Наборы'}default{'Приложения'}}
 foreach($nav in @(@{Button=$GoCatalog;Key='catalog'},@{Button=$GoBundles;Key='bundles'},@{Button=$GoResults;Key='results'},@{Button=$GoLog;Key='log'})){
  if($nav.Key -eq $tab){$nav.Button.Background='#222B24';$nav.Button.BorderBrush='#35463A';$nav.Button.Foreground='#C1E7C9'}
  else{$nav.Button.Background='Transparent';$nav.Button.BorderBrush='Transparent';$nav.Button.Foreground='#DCE4DD'}
 }
}
function Category([string]$key){
 $Catalog.Items.Clear()
 foreach($name in $script:groups[$key]){
  $known=$script:catalogPackages[$name]
  if($known){[void]$Catalog.Items.Add((App $name $known.Id $known.Source 'Catalog' ''))}
  else{[void]$Catalog.Items.Add((App $name '' '' '' ''))}
 }
 foreach($button in $Categories.Children){if($button.Tag -eq $key){$button.Background='#2A382D';$button.BorderBrush='#526C56';$button.Foreground='#C1E7C9'}else{$button.Background='#1B211D';$button.BorderBrush='#303832';$button.Foreground='#DCE4DD'}}
}
foreach($key in @($script:groups.Keys)){
 $b=New-Object Windows.Controls.Button
 $b.Style=$win.FindResource('CategoryButton');$b.Content=$key;$b.Tag=$key
 $b.Margin=New-Object Windows.Thickness(0,0,8,8)
 $b.Add_Click({param($sender,$e)Category ([string]$sender.Tag)})
 [void]$Categories.Children.Add($b)
}
$script:op=$null
$script:paths=@()
function Remove-Temp {
 foreach($p in $script:paths){try{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}catch{}}
 $script:paths=@()
}
function Get-GSUiObjectValue($Object,[string]$Name,$Default=$null){
 if($null -eq $Object){return $Default}
 $property=$Object.PSObject.Properties[$Name]
 if($null -eq $property -or $null -eq $property.Value){return $Default}
 return $property.Value
}
function Set-GSUiControlText([string]$Name,[string]$Value){
 $control=$win.FindName($Name)
 if($null -ne $control -and $null -ne $control.PSObject.Properties['Text']){$control.Text=$Value}
}
function Run-Core([hashtable]$req){
 if($null -ne $script:op){return}
 Remove-Temp
 $id=[guid]::NewGuid().ToString('N');$dir=[IO.Path]::GetTempPath()
 $requestFile=Join-Path $dir ('gsnext-'+$id+'-request.json')
 $outputFile=Join-Path $dir ('gsnext-'+$id+'-output.log')
 $resultFile=Join-Path $dir ('gsnext-'+$id+'-result.json')
 $progressFile=Join-Path $dir ('gsnext-'+$id+'-progress.json')
 $previewFile=Join-Path $dir ('gsnext-'+$id+'-preview.json')
 $script:paths=@($requestFile,$outputFile,$resultFile,$progressFile,$previewFile)
 $req.ResultFile=$resultFile;$req.ProgressFile=$progressFile;$req.PreviewFile=$previewFile
 $req.OperationId='NEXT-'+$id
 if(-not $req.ContainsKey('AgreementConsent')){$req.AgreementConsent=$false}
 if(-not $req.ContainsKey('AllowServiceChanges')){$req.AllowServiceChanges=$false}
 $req.AcceptAgreements=[bool]$req.AgreementConsent
 [IO.File]::WriteAllText($requestFile,(ConvertTo-Json -InputObject $req -Depth 6),[Text.UTF8Encoding]::new($false))
 $p=New-Object Diagnostics.ProcessStartInfo
 $p.FileName=Join-Path $PSHOME 'powershell.exe'
 $p.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $root 'GarantStore.Core.ps1')+'" -RequestFile "'+$requestFile+'" -OutputFile "'+$outputFile+'"'
 $p.UseShellExecute=$false;$p.CreateNoWindow=$true
 $process=[Diagnostics.Process]::Start($p)
 if($null -eq $process){throw 'Failed to launch Core'}
 $opQuery=if($req.ContainsKey('Query')){[string]$req.Query}else{''}
 $opSource=if($req.ContainsKey('Source')){[string]$req.Source}else{''}
 $Log.Clear()
 $script:op=[pscustomobject]@{Id=$req.OperationId;Process=$process;Stopped=$false;BundlePosition='';BundleItem='';LogOffset=[long]0;LogDecoder=(New-Object Text.UTF8Encoding($false)).GetDecoder();Action=$req.Action;Out=$outputFile;Result=$resultFile;Preview=$previewFile;Progress=$progressFile;SeenPreview=$false;Query=$opQuery;Source=$opSource;AgreementConsent=[bool]$req.AgreementConsent;Request=@{}+$req}
 $Search.IsEnabled=$false;$Install.IsEnabled=$false;$BundleInstall.IsEnabled=$false;$Stop.IsEnabled=$true
 $Status.Text='Выполняется: '+$req.Action;$Detail.Text='Подготовка...';$Progress.IsIndeterminate=$true
 $tick.Start()
}
function Stop-GSOperationProcessTree($Process){
 # Process.Kill() in .NET Framework ends only Core; WinGet and the installer it
 # launched would keep running unseen. taskkill /T walks the tree while Core is
 # still alive, so it must run before the fallback Kill(). Elevated children that
 # WinGet started through UAC cannot be ended from a normal process and finish on
 # their own; the elevated service helper restores services when Core exits.
 if($null -eq $Process){return}
 try{
  if(-not $Process.HasExited){
   $taskkill=Join-Path $env:WINDIR 'System32\taskkill.exe'
   $killer=Start-Process -FilePath $taskkill -ArgumentList @('/PID',[string]$Process.Id,'/T','/F') -WindowStyle Hidden -PassThru
   [void]$killer.WaitForExit(5000)
  }
 }catch{}
 try{if(-not $Process.HasExited){$Process.Kill()}}catch{}
}
function Read-GSOperationLogDelta($Operation){
 # Append only the bytes Core wrote since the previous tick instead of re-reading
 # and re-rendering the whole log twice a second. A stateful decoder keeps UTF-8
 # characters that straddle two reads intact; the view keeps the latest ~300 KB.
 if($null -eq $Operation -or -not [IO.File]::Exists($Operation.Out)){return}
 $stream=New-Object IO.FileStream($Operation.Out,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
 try{
  if($stream.Length -lt $Operation.LogOffset){$Operation.LogOffset=0;$Operation.LogDecoder=(New-Object Text.UTF8Encoding($false)).GetDecoder();$Log.Clear()}
  if($stream.Length -le $Operation.LogOffset){return}
  [void]$stream.Seek($Operation.LogOffset,[IO.SeekOrigin]::Begin)
  $count=[int][Math]::Min($stream.Length-$Operation.LogOffset,1048576)
  $buffer=New-Object byte[] $count
  $read=$stream.Read($buffer,0,$count)
  if($read -le 0){return}
  $Operation.LogOffset+=$read
  $chars=New-Object char[] ([Text.Encoding]::UTF8.GetMaxCharCount($read))
  $length=$Operation.LogDecoder.GetChars($buffer,0,$read,$chars,0)
  if($length -gt 0){
   $Log.AppendText((New-Object string($chars,0,$length)).TrimStart([char]0xFEFF))
   if($Log.Text.Length -gt 400000){$Log.Text=$Log.Text.Substring($Log.Text.Length-300000)}
   $Log.ScrollToEnd()
  }
 }finally{$stream.Dispose()}
}
function Search-App([bool]$AgreementConsent=$false) {
 $q=$Query.Text.Trim();if(-not $q){$Status.Text='Введите название программы';return}
 $Results.Items.Clear();$ResultCount.Text='Идёт поиск: '+$q;Page 'results'
 Run-Core @{Action='search';Query=$q;Source=[string]$Source.SelectedItem.Tag;AgreementConsent=$AgreementConsent}
}
function Load-Results($list){
 $Results.Items.Clear()
 foreach($v in @($list)){
  if($null -eq $v){continue}
  [void]$Results.Items.Add((App ([string]$v.Name) ([string]$v.Id) ([string]$v.Source) ([string]$v.Status) ([string]$v.Version) ([string]$v.InstalledVersion) ([string]$v.AvailableVersion)))
 }
 $ResultCount.Text=([string]$Results.Items.Count)+' найдено'
}
# --- Bundles: curated sets of programs installed one after another --------------
$script:bundles=@()
$script:currentBundle=$null
$script:bundleRows=@()
$bundleFile=Join-Path $root 'Bundles.json'
if(Test-Path -LiteralPath $bundleFile){
 try{$script:bundles=@((Get-Content -LiteralPath $bundleFile -Raw -Encoding UTF8|ConvertFrom-Json).Bundles)}
 catch{Write-GSUiFailure -Component 'Bundles.Load' -Exception $_.Exception}
}
function New-GSBundleText([string]$Text,[double]$Size,[string]$Color,[string]$Weight='Normal'){
 $t=New-Object Windows.Controls.TextBlock
 $t.Text=$Text;$t.FontSize=$Size;$t.Foreground=$Color;$t.FontWeight=$Weight;$t.TextWrapping='Wrap'
 return $t
}
function Show-GSBundleCards {
 $script:currentBundle=$null;$script:bundleRows=@()
 $BundleCards.Visibility='Visible';$BundleItems.Visibility='Collapsed'
 $BundleBack.Visibility='Collapsed';$BundleInstall.Visibility='Collapsed';$BundleToggle.Visibility='Collapsed'
 $BundleTitle.Text='Наборы программ'
 $BundleSubtitle.Text='Выберите набор: программы установятся по очереди, уже установленные будут пропущены'
 $BundleSummary.Text=if($script:bundles.Count){[string]$script:bundles.Count+' наборов'}else{'Файл наборов не найден'}
}
function Initialize-GSBundleCards {
 $BundleCards.Children.Clear()
 foreach($bundle in $script:bundles){
  $card=New-Object Windows.Controls.Button
  $card.Style=$win.FindResource('ButtonStyle')
  $card.Width=264;$card.Height=118;$card.Margin=New-Object Windows.Thickness(0,0,12,12)
  $card.HorizontalContentAlignment='Left';$card.VerticalContentAlignment='Top';$card.Padding=New-Object Windows.Thickness(16,14,16,14)
  $card.Tag=$bundle
  [Windows.Automation.AutomationProperties]::SetAutomationId($card,'Bundle-'+[string]$bundle.Id)
  $panel=New-Object Windows.Controls.StackPanel
  [void]$panel.Children.Add((New-GSBundleText ([string]$bundle.Title) 16 '#EEF2EE' 'SemiBold'))
  $description=New-GSBundleText ([string]$bundle.Description) 11 '#89938B';$description.Margin=New-Object Windows.Thickness(0,6,0,0);$description.MaxHeight=46
  [void]$panel.Children.Add($description)
  $count=New-GSBundleText ([string]@($bundle.Items).Count+' программ') 11 '#70E2AA';$count.Margin=New-Object Windows.Thickness(0,8,0,0)
  [void]$panel.Children.Add($count)
  $card.Content=$panel
  $card.Add_Click({param($sender,$e)Open-GSBundle $sender.Tag})
  [void]$BundleCards.Children.Add($card)
 }
}
function Open-GSBundle($Bundle,[switch]$SkipStateCheck){
 $script:currentBundle=$Bundle
 $BundleCards.Visibility='Collapsed';$BundleItems.Visibility='Visible'
 $BundleBack.Visibility='Visible';$BundleInstall.Visibility='Visible';$BundleToggle.Visibility='Visible'
 $BundleTitle.Text=[string]$Bundle.Title;$BundleSubtitle.Text=[string]$Bundle.Description
 $BundleItems.Children.Clear()
 $rows=New-Object System.Collections.ArrayList
 foreach($item in @($Bundle.Items)){
  $box=New-Object Windows.Controls.CheckBox
  $box.IsChecked=[bool]$item.Default;$box.Margin=New-Object Windows.Thickness(0,0,0,10);$box.Foreground='#EEF2EE';$box.VerticalContentAlignment='Center'
  [Windows.Automation.AutomationProperties]::SetAutomationId($box,'BundleItem-'+[string]$item.Id)
  $panel=New-Object Windows.Controls.StackPanel;$panel.Margin=New-Object Windows.Thickness(8,0,0,0)
  [void]$panel.Children.Add((New-GSBundleText ([string]$item.Name) 14 '#EEF2EE' 'Medium'))
  $state=New-GSBundleText ($(if($SkipStateCheck){[string]$item.Id}else{'Проверяем статус...'})) 11 '#89938B'
  [void]$panel.Children.Add($state)
  $box.Content=$panel
  $box.Add_Click({Update-GSBundleSummary})
  [void]$BundleItems.Children.Add($box)
  [void]$rows.Add([pscustomobject]@{Item=$item;CheckBox=$box;State=$state})
 }
 $script:bundleRows=@($rows.ToArray())
 Update-GSBundleSummary
 Page 'bundles'
 if(-not $SkipStateCheck){
  if($null -eq $script:op){Run-Core @{Action='bundlestate';Items=@(Get-GSBundleRequestItems -All)}}
  else{foreach($row in $script:bundleRows){$row.State.Text='Статус проверится после текущей операции'}}
 }
}
function Get-GSBundleRequestItems([switch]$All,[string[]]$OnlyIds=@()){
 $selected=@($script:bundleRows|Where-Object{$All -or ([bool]$_.CheckBox.IsChecked -and $_.CheckBox.IsEnabled)})
 if($OnlyIds.Count){$selected=@($script:bundleRows|Where-Object{$OnlyIds -contains [string]$_.Item.Id})}
 return @($selected|ForEach-Object{@{Name=[string]$_.Item.Name;Id=[string]$_.Item.Id;Source=[string]$_.Item.Source}})
}
function Update-GSBundleSummary {
 $checked=@($script:bundleRows|Where-Object{[bool]$_.CheckBox.IsChecked -and $_.CheckBox.IsEnabled}).Count
 $BundleSummary.Text='Выбрано: '+$checked+' из '+$script:bundleRows.Count
 $BundleInstall.IsEnabled=($checked -gt 0 -and $null -eq $script:op)
 $BundleInstall.Content=if($checked -gt 0){'Установить выбранное ('+$checked+')'}else{'Установить выбранное'}
}
function Set-GSBundleRowState($Row,[string]$Text,[string]$Color,[bool]$Selectable,[object]$Checked=$null){
 $Row.State.Text=$Text;$Row.State.Foreground=$Color
 $Row.CheckBox.IsEnabled=$Selectable
 if(-not $Selectable){$Row.CheckBox.IsChecked=$false}elseif($null -ne $Checked){$Row.CheckBox.IsChecked=[bool]$Checked}
}
function Find-GSBundleRow([string]$Id){
 return @($script:bundleRows|Where-Object{[string]::Equals([string]$_.Item.Id,$Id,[StringComparison]::OrdinalIgnoreCase)})|Select-Object -First 1
}
function Update-GSBundleStates($States){
 foreach($state in @($States)){
  $row=Find-GSBundleRow ([string]$state.Id);if($null -eq $row){continue}
  switch([string]$state.Status){
   'Installed'{Set-GSBundleRowState $row ('Установлено'+$(if($state.InstalledVersion){' · '+[string]$state.InstalledVersion}else{''})) '#70E2AA' $false}
   'StoreUpdateUnknown'{Set-GSBundleRowState $row 'Установлено' '#70E2AA' $false}
   'UpdateAvailable'{Set-GSBundleRowState $row ('Доступно обновление · '+[string]$state.AvailableVersion) '#E6C36A' $true $true}
   'NotInstalled'{Set-GSBundleRowState $row 'Не установлено' '#ADB7AF' $true}
   default{Set-GSBundleRowState $row 'Статус не определён: будет проверен при установке' '#89938B' $true}
  }
 }
 Update-GSBundleSummary
}
function Show-GSBundleOutcome($Data){
 if($null -eq $Data){return}
 foreach($outcome in @($Data.Items)){
  $row=Find-GSBundleRow ([string]$outcome.Id);if($null -eq $row){continue}
  switch([string]$outcome.Outcome){
   'InstalledVerified'{Set-GSBundleRowState $row 'Установлено и проверено' '#70E2AA' $false}
   'UpdateVerified'{Set-GSBundleRowState $row 'Обновлено и проверено' '#70E2AA' $false}
   'AlreadyCurrent'{Set-GSBundleRowState $row 'Уже было установлено' '#70E2AA' $false}
   'StoreUpdateUnknown'{Set-GSBundleRowState $row 'Уже было установлено' '#70E2AA' $false}
   default{
    $reason=if([string]$outcome.ErrorCode -eq 'StoreServiceConsentRequired'){'нужно разрешить службы Microsoft Store'}else{[string]$outcome.Message}
    Set-GSBundleRowState $row ('Не установлено: '+$reason) '#E58A7A' $true $true
   }
  }
 }
 Update-GSBundleSummary
 $Status.Text=if([int]$Data.Failed -eq 0){'Набор установлен'}else{'Набор установлен частично'}
 $Detail.Text='Установлено: '+[int]$Data.Installed+' · уже было: '+[int]$Data.AlreadyPresent+' · ошибок: '+[int]$Data.Failed
}
function Format-GSBundleProgress($Progress){
 # Core reports "Bundle i/N" with the program name; inner pipeline stages keep
 # the position visible instead of replacing it.
 if([string]$Progress.Stage -match '^Bundle (\d+)/(\d+)$'){$script:op.BundlePosition='Набор: программа '+$Matches[1]+' из '+$Matches[2];$script:op.BundleItem=[string]$Progress.Detail}
 if($script:op.BundlePosition){$Status.Text=$script:op.BundlePosition;$Detail.Text=$script:op.BundleItem}
}
function Complete-GSBundleOperation($Operation,$Result){
 if($Operation.Action -eq 'bundlestate'){
  $rows=Get-GSUiObjectValue $Result 'Results' $null
  if($null -ne $rows){Update-GSBundleStates $rows;$Status.Text='Готово';$Detail.Text='Статус программ набора проверен'}
  else{foreach($row in $script:bundleRows){if($row.State.Text -eq 'Проверяем статус...'){$row.State.Text='Статус не определён: будет проверен при установке'}}}
  return
 }
 if($Operation.Action -ne 'bundle'){return}
 $data=Get-GSUiObjectValue $Result 'Data' $null
 Show-GSBundleOutcome $data
 $consentIds=@(@(Get-GSUiObjectValue $data 'NeedsServiceConsent' @())|Where-Object{$_})
 if($consentIds.Count -and -not [bool]$Operation.Request.AllowServiceChanges){
  $retryItems=@(Get-GSBundleRequestItems -OnlyIds $consentIds)
  $prompt='Для установки приложений из Microsoft Store ('+$retryItems.Count+') нужен временный запуск системных служб.'+"`n`n"+'Windows запросит права администратора. Исходные настройки служб будут восстановлены автоматически. Разрешить и повторить установку только этих приложений?'
  $retry={
   try{
    $choice=[Windows.MessageBox]::Show($win,$prompt,'Требуются службы Microsoft Store',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Warning)
    if($choice -eq [Windows.MessageBoxResult]::Yes){Run-Core @{Action='bundle';Items=$retryItems;AgreementConsent=$true;AllowServiceChanges=$true}}
   }catch{Write-GSUiFailure -Component 'Bundle.ServiceConsentRetry' -Exception $_.Exception}
  }.GetNewClosure()
  [void]$win.Dispatcher.BeginInvoke([Action]$retry,[Windows.Threading.DispatcherPriority]::Background)
 }
}
$BundleBack.Add_Click({Show-GSBundleCards})
$BundleToggle.Add_Click({
 $enabled=@($script:bundleRows|Where-Object{$_.CheckBox.IsEnabled})
 $allChecked=(@($enabled|Where-Object{-not [bool]$_.CheckBox.IsChecked}).Count -eq 0)
 foreach($row in $enabled){$row.CheckBox.IsChecked=-not $allChecked}
 Update-GSBundleSummary
})
$BundleInstall.Add_Click({
 $items=@(Get-GSBundleRequestItems)
 if($items.Count -eq 0 -or $null -ne $script:op){return}
 $names=($items|ForEach-Object{$_.Name}) -join ', '
 $message='Установить '+$items.Count+' программ из набора «'+[string]$script:currentBundle.Title+'»?'+"`n`n"+$names+"`n`n"+'Программы ставятся по очереди. Windows может запросить права администратора для некоторых из них. Нажимая «Да», вы принимаете соглашения пакетов и источников.'
 if([Windows.MessageBox]::Show($win,$message,'Garant Store',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Question) -ne [Windows.MessageBoxResult]::Yes){return}
 try{Run-Core @{Action='bundle';Items=$items;AgreementConsent=$true}}catch{$Status.Text=$_.Exception.Message}
})
$GoBundles.Add_Click({if($null -eq $script:currentBundle){Show-GSBundleCards};Page 'bundles'})
Initialize-GSBundleCards
Show-GSBundleCards
$tick=New-Object Windows.Threading.DispatcherTimer
$tick.Interval=[TimeSpan]::FromMilliseconds(450)
$tick.Add_Tick({
 if($null -eq $script:op){$tick.Stop();return}
 $o=$script:op
 $agreementRetry=$false
 $serviceConsentRetry=$false
 try{
  Read-GSOperationLogDelta $o
  if([IO.File]::Exists($o.Progress)){
   $p=Get-Content $o.Progress -Raw | ConvertFrom-Json
   if($null -ne $p.Stage){$Status.Text=[string]$p.Stage}
   if($null -ne $p.Detail){$Detail.Text=[string]$p.Detail}
   if($null -ne $p.Percent -and [double]$p.Percent -ge 0 -and [double]$p.Percent -le 100){$Progress.IsIndeterminate=$false;$Progress.Value=[double]$p.Percent}
   if($o.Action -eq 'bundle'){Format-GSBundleProgress $p}
  }
  if($o.Action -eq 'search' -and -not $o.SeenPreview -and [IO.File]::Exists($o.Preview)){
   $v=Get-Content $o.Preview -Raw | ConvertFrom-Json
   $previewRows=Get-GSUiObjectValue $v 'Results' $null
   if($null -ne $previewRows){Load-Results $previewRows;$o.SeenPreview=$true}
  }
 }catch{$Detail.Text=$_.Exception.Message}
 if(-not $o.Process.HasExited){return}
 $tick.Stop()
 try{Read-GSOperationLogDelta $o}catch{}
 try{
  if([IO.File]::Exists($o.Result)){
   $v=Get-Content $o.Result -Raw | ConvertFrom-Json
   $resultErrorCode=[string](Get-GSUiObjectValue $v 'ErrorCode' '')
   $resultStatus=[string](Get-GSUiObjectValue $v 'Status' '')
   $resultMessage=[string](Get-GSUiObjectValue $v 'Message' 'Операция завершилась без подробного сообщения.')
   if($o.Action -eq 'search' -and -not $o.AgreementConsent -and $resultErrorCode -eq 'SourceAgreementsRequired'){$agreementRetry=$true;$Status.Text='Требуется согласие';$Detail.Text='WinGet запросил согласие с условиями источника перед продолжением поиска.'}
   if($o.Action -eq 'install' -and $resultErrorCode -eq 'StoreServiceConsentRequired'){$serviceConsentRetry=$true}
   $resultRows=Get-GSUiObjectValue $v 'Results' $null
   if($o.Action -eq 'search' -and $null -ne $resultRows){Load-Results $resultRows}
   $resultSuccess=[bool](Get-GSUiObjectValue $v 'Success' $false)
   $Status.Text=if($resultSuccess){switch($resultStatus){'AlreadyCurrent'{'Актуально'}'StoreUpdateUnknown'{'Проверка не завершена'}'UpdateVerified'{'Обновлено'}'InstalledVerified'{'Установлено'}'RepairVerified'{'Поиск проверен'}'RepairPartial'{'Частично проверено'}default{'Готово'}}}else{'Ошибка'}
   $Detail.Text=switch($resultStatus){
    'AlreadyCurrent'{'Приложение уже установлено и обновление не требуется.'}
    'StoreUpdateUnknown'{'Приложение установлено, но наличие обновления подтвердить не удалось. Изменений не внесено.'}
    'UpdateVerified'{'Установка обновления подтверждена. Запуск приложения не проверялся.'}
    'InstalledVerified'{'Установка приложения подтверждена. Запуск приложения не проверялся.'}
    'RepairPartial'{$resultMessage}
    default{$resultMessage}
   }
   if($o.Action -in @('bundlestate','bundle')){Complete-GSBundleOperation $o $v}
  }elseif([bool]$o.Stopped){
   $Status.Text='Остановлено'
   $Detail.Text=if($o.Action -in @('install','bundle')){'Операция прервана. Если установщик уже вносил изменения, проверьте приложение или повторите установку.'}else{'Операция прервана пользователем.'}
  }else{$Status.Text='Операция завершилась без результата';$Detail.Text='Откройте журнал'}
 }catch{$Status.Text='Ошибка обработки результата';$Detail.Text=$_.Exception.Message}
 $o.Process.Dispose();$script:op=$null;$Progress.IsIndeterminate=$false
 $Search.IsEnabled=$true;$Stop.IsEnabled=$false
 $Install.IsEnabled=($null -ne $Results.SelectedItem)
 Update-GSBundleSummary
 Remove-Temp
 if($agreementRetry){
  $query=$o.Query;$source=$o.Source
  $prompt='Для поиска Garant Store запросил согласие с условиями источника Microsoft Store.'+"`n`n"+
   'WinGet передаст двухбуквенный код региона Windows. Условия: https://aka.ms/microsoft-store-terms-of-transaction'+"`n`n"+
   'Принять условия и повторить поиск?'
  $retryAction={
   try {
    $choice=[Windows.MessageBox]::Show($win,$prompt,'Microsoft Store — согласие источника',[Windows.MessageBoxButton]::YesNoCancel,[Windows.MessageBoxImage]::Question)
    if($choice -eq [Windows.MessageBoxResult]::Yes){
     $queryBox=$win.FindName('Query');$queryBox.Text=$query
     Run-Core @{Action='search';Query=$query;Source=$source;AgreementConsent=$true}
    }elseif($choice -eq [Windows.MessageBoxResult]::No -and [string]::IsNullOrWhiteSpace($source)){
     $queryBox=$win.FindName('Query');$queryBox.Text=$query;Set-GSUiControlText 'Detail' 'Согласие не принято. Выполняю поиск только в источнике WinGet.'
     Run-Core @{Action='search';Query=$query;Source='winget';AgreementConsent=$false}
    }else{
     Set-GSUiControlText 'Status' $(if($choice -eq [Windows.MessageBoxResult]::Cancel){'Поиск отменён'}else{'Согласие отклонено'})
     Set-GSUiControlText 'Detail' $(if($choice -eq [Windows.MessageBoxResult]::Cancel){'Поиск Microsoft Store отменён. Источник не запускался повторно.'}else{'Поиск Microsoft Store отменён: согласие с условиями источника не принято.'})
    }
   } catch {
    Write-GSUiFailure -Component 'Search.ConsentRetry' -Exception $_.Exception -OperationId $o.Id
    Set-GSUiControlText 'Status' 'Не удалось повторить поиск';Set-GSUiControlText 'Detail' $_.Exception.Message
   }
  }.GetNewClosure()
  [void]$win.Dispatcher.BeginInvoke([Action]$retryAction,[Windows.Threading.DispatcherPriority]::Background)
 }
 if($serviceConsentRetry){
  $retryRequest=@{}+$o.Request
  $serviceMessage=[string](Get-GSUiObjectValue $v 'Message' 'Системные службы должны быть запущены для Microsoft Store.')
  $prompt='Для установки этого приложения необходим временный запуск системных служб.'+"`n`n"+
   $serviceMessage+"`n`n"+
   'Garant Store не изменял службы. Разрешить изменить только перечисленные службы и повторить установку? Windows запросит права администратора. Исходные настройки служб будут восстановлены автоматически после завершения или остановки операции. Политики Windows не обходятся; при установленном запрете операция будет остановлена.'
  $retryAction={
   try{
    $choice=[Windows.MessageBox]::Show($win,$prompt,'Требуются службы Microsoft Store',[Windows.MessageBoxButton]::YesNoCancel,[Windows.MessageBoxImage]::Warning)
    if($choice -eq [Windows.MessageBoxResult]::Yes){$retryRequest.AllowServiceChanges=$true;Run-Core $retryRequest}
    else{Set-GSUiControlText 'Status' 'Установка отменена';Set-GSUiControlText 'Detail' 'Системные службы не изменялись.'}
   }catch{Write-GSUiFailure -Component 'Store.ServiceConsentRetry' -Exception $_.Exception -OperationId $o.Id;Set-GSUiControlText 'Status' 'Не удалось повторить установку';Set-GSUiControlText 'Detail' $_.Exception.Message}
  }.GetNewClosure()
  [void]$win.Dispatcher.BeginInvoke([Action]$retryAction,[Windows.Threading.DispatcherPriority]::Background)
 }
})
$Search.Add_Click({try{Search-App}catch{$Status.Text=$_.Exception.Message}})
$Query.Add_KeyDown({param($sender,$e)if($e.Key -eq 'Return'){Search-App}})
function Open-GSCatalogPackage($Item){
 # Known identity: show it as the selected result right away. Status stays
 # unknown here; the install action checks the exact installed state first.
 $Results.Items.Clear()
 [void]$Results.Items.Add((App ([string]$Item.Name) ([string]$Item.Id) ([string]$Item.Source) '' ''))
 $ResultCount.Text='Из подборки · '+[string]$Item.Id
 Page 'results'
 $Results.SelectedIndex=0
}
$Catalog.Add_SelectionChanged({
 $v=$Catalog.SelectedItem
 if($null -eq $v){return}
 $Catalog.SelectedItem=$null
 $Query.Text=[string]$v.Name
 if($v.Id -and $null -eq $script:op){Open-GSCatalogPackage $v}else{Search-App}
})
$GoCatalog.Add_Click({Page 'catalog'})
$GoResults.Add_Click({Page 'results'})
$GoLog.Add_Click({Page 'log'})
$Results.Add_SelectionChanged({
 $v=$Results.SelectedItem
 $Install.IsEnabled=($null -ne $v -and $null -eq $script:op)
 if($null -eq $v){$Selection.Text='Выберите приложение';$Install.Content='Установить выбранное';return}
 switch([string]$v.Status){
  'Installed'{$Selection.Text=if($v.InstalledVersion){'Уже установлено · версия '+$v.InstalledVersion}else{'Уже установлено · обновление не требуется'};$Install.Content='Проверить обновления'}
  'UpdateAvailable'{$Selection.Text='Доступно обновление · '+[string]$v.AvailableVersion;$Install.Content='Обновить'}
  'StoreUpdateUnknown'{$Selection.Text='Приложение установлено · обновление не подтверждено';$Install.Content='Повторить проверку'}
  'Unknown'{$Selection.Text='Не удалось проверить статус · '+[string]$v.Source;$Install.Content='Повторить проверку'}
  default{$Selection.Text=[string]$v.Name+' · '+[string]$v.Source;$Install.Content='Установить выбранное'}
 }
})
$Install.Add_Click({
 $v=$Results.SelectedItem;if($null -eq $v){return}
 $message=if($v.Status -eq 'Installed' -or $v.Status -eq 'StoreUpdateUnknown'){'Проверить состояние и наличие обновления для '+$v.Name+' ('+$v.Id+')? Программа не будет менять приложение, если оно уже актуально.'}else{'Установить или обновить '+$v.Name+' ('+$v.Id+')? Подтвердите принятие соглашений пакета и источника.'}
 if([Windows.MessageBox]::Show($message,'Garant Store','YesNo','Question') -ne 'Yes'){return}
 try{Run-Core @{Action='install';Name=$v.Name;Id=$v.Id;Source=$v.Source;KnownStatus=$v.Status;AvailableVersion=$v.Version;AgreementConsent=$true}}catch{$Status.Text=$_.Exception.Message}
})
$Doctor.Add_Click({Page 'log';try{Run-Core @{Action='doctor'}}catch{$Status.Text=$_.Exception.Message}})
$Repair.Add_Click({
 if([Windows.MessageBox]::Show('Восстановить WinGet?','Garant Store','YesNo','Warning') -eq 'Yes'){Page 'log';try{Run-Core @{Action='repairwinget'}}catch{$Status.Text=$_.Exception.Message}}
})
$Stop.Add_Click({
 $o=$script:op;if($null -eq $o){return}
 if($o.Action -in @('install','bundle')){
  $answer=[Windows.MessageBox]::Show($win,'Остановка во время установки может оставить приложение установленным не полностью. Остановить операцию?','Garant Store',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Warning)
  if($answer -ne [Windows.MessageBoxResult]::Yes){return}
 }
 $o.Stopped=$true;$Stop.IsEnabled=$false;$Status.Text='Остановка...'
 Stop-GSOperationProcessTree $o.Process
})
$win.Add_Closed({if($null -ne $script:op){Stop-GSOperationProcessTree $script:op.Process};Remove-Temp})
Category 'Популярные';Page 'catalog'
if($env:GS_WPF_SMOKE -eq '1'){
 $smoke=New-Object Windows.Threading.DispatcherTimer
 $smoke.Interval=[TimeSpan]::FromMilliseconds(800)
 $smoke.Add_Tick({
  $smoke.Stop();$result='CLOSED'
  try{
   if($Catalog.Items.Count -lt 5){throw 'CATALOG_EMPTY'}
   $imageFolder=[string]$env:GS_WPF_SCREENSHOT_DIR
   if($imageFolder){
    [IO.Directory]::CreateDirectory($imageFolder) | Out-Null
    foreach($state in @('normal','wide')){
     if($state -eq 'wide'){$win.Width=1600;$win.Height=920}
     $win.UpdateLayout()
     $width=[int][Math]::Ceiling($win.ActualWidth)
     $height=[int][Math]::Ceiling($win.ActualHeight)
     if($width -lt 800 -or $height -lt 500){throw 'INVALID_WINDOW_SIZE'}
     $bmp=New-Object Windows.Media.Imaging.RenderTargetBitmap($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
     $bmp.Render($win)
     $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
     $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
     $stream=[IO.File]::Create((Join-Path $imageFolder ('garant-next-'+$state+'.png')))
     try{$encoder.Save($stream)}finally{$stream.Dispose()}
    }
   }else{$win.Width=1600;$win.Height=920;$win.UpdateLayout()}
  }catch{$result='SMOKE_FAILED_'+$_.Exception.Message}
  if($result -eq 'CLOSED'){
   try{
    if($BundleCards.Children.Count -lt 4){throw ('BUNDLES_MISSING_'+$BundleCards.Children.Count)}
    Open-GSBundle $script:bundles[0] -SkipStateCheck
    if($BundleItems.Children.Count -lt 3){throw 'BUNDLE_ITEMS_MISSING'}
    if(-not $BundleInstall.IsEnabled){throw 'BUNDLE_INSTALL_DISABLED_WITH_DEFAULTS'}
    $imageFolder=[string]$env:GS_WPF_SCREENSHOT_DIR
    if($imageFolder){
     $win.UpdateLayout()
     $bmp=New-Object Windows.Media.Imaging.RenderTargetBitmap([int][Math]::Ceiling($win.ActualWidth),[int][Math]::Ceiling($win.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32)
     $bmp.Render($win);$encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
     $stream=[IO.File]::Create((Join-Path $imageFolder 'garant-next-bundle.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
    }
    Show-GSBundleCards;Page 'catalog'
   }catch{$result='BUNDLES_FAILED_'+$_.Exception.Message}
  }
  if($result -eq 'CLOSED'){try{Show-About}catch{$result='ABOUT_FAILED_'+$_.Exception.Message}}
  if($env:GS_WPF_SMOKE_MARKER){[IO.File]::WriteAllText($env:GS_WPF_SMOKE_MARKER,$result,[Text.UTF8Encoding]::new($false))}
  $win.Close()
 })
 $win.Add_ContentRendered({$smoke.Start()})
}
$win.Add_SourceInitialized({Write-GSStartupStage 'native-window-initialized'})
$win.Add_ContentRendered({Write-GSStartupStage 'main-window-rendered'})
Write-GSStartupStage 'entering-show-dialog'
[void]$win.ShowDialog()

