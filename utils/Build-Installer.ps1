<#
.SYNOPSIS
    Empaqueta las distribuciones portables de ApexPad (x64 y x86) en archivos .zip
    y compila instaladores GUI autocontenidos (.exe) para Windows.
#>
[CmdletBinding()]
param(
    [string]$Version = "1.0.0",
    [string]$DistDir = "",
    [string]$IconPath = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($DistDir)) {
    $DistDir = Join-Path $repoRoot "dist"
}
if ([string]::IsNullOrWhiteSpace($IconPath)) {
    $IconPath = Join-Path $repoRoot "ApexPad\ApexPad.ico"
}

# Verificamos el compilador C# nativo de .NET Framework 4.x incluido en Windows.
$cscPath = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $cscPath)) {
    throw "No se encontro csc.exe en $cscPath"
}

if (-not (Test-Path $IconPath)) {
    throw "No se encontro el icono en $IconPath"
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Archivos y carpetas de sesion local que nunca deben incluirse en paquetes publicos.
$excludedFiles = @(
    "Profiles.xml",
    "Auto Profiles.xml",
    "Actions.xml",
    "ControllerConfigs.xml",
    "OutputSlots.xml",
    "LinkedProfiles.xml"
)
$excludedDirs = @("Logs")

<#
.SYNOPSIS
    Copia una carpeta publicada filtrando logs locales y configuraciones personales,
    y genera su archivo .zip portable limpio.
#>
function New-CleanPortableZip {
    param(
        [string]$SourceDir,
        [string]$ZipPath,
        [string]$StagingDir
    )

    if (-not (Test-Path (Join-Path $SourceDir "ApexPad.exe"))) {
        throw "No existe ApexPad.exe en $SourceDir"
    }

    if (Test-Path $StagingDir) {
        Remove-Item -Path $StagingDir -Recurse -Force
    }
    if (Test-Path $ZipPath) {
        Remove-Item -Path $ZipPath -Force
    }

    New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null

    Get-ChildItem -Path $SourceDir -Force | ForEach-Object {
        $item = $_
        if ($item.PSIsContainer) {
            if ($excludedDirs -notcontains $item.Name) {
                Copy-Item -Path $item.FullName -Destination (Join-Path $StagingDir $item.Name) -Recurse -Force
            }
        }
        else {
            if (($excludedFiles -notcontains $item.Name) -and ($item.Extension -ne ".pdb")) {
                Copy-Item -Path $item.FullName -Destination (Join-Path $StagingDir $item.Name) -Force
            }
        }
    }

    Write-Host " -> Comprimiendo $ZipPath..." -ForegroundColor Cyan
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $StagingDir,
        $ZipPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )
}

# Codigo fuente C# 5 compatible con csc.exe (.NET Framework 4.x) para el instalador GUI.
$installerSourceTemplate = @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Instalador de ApexPad")]
[assembly: AssemblyProduct("ApexPad")]
[assembly: AssemblyCompany("Flavio Morales")]
[assembly: AssemblyCopyright("GNU GPLv3 - Flavio Morales (Flavio6931)")]
[assembly: AssemblyVersion("__VERSION__.0")]
[assembly: AssemblyFileVersion("__VERSION__.0")]

namespace ApexPadSetup
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new InstallerForm());
        }
    }

    internal sealed class InstallerForm : Form
    {
        private const string AppName = "ApexPad";
        private const string AppVersion = "__VERSION__";
        private const string ArchLabel = "__ARCH__";
        private const string ResourceName = "ApexPad.payload.zip";

        private readonly TextBox txtPath;
        private readonly Button btnBrowse;
        private readonly CheckBox chkDesktop;
        private readonly CheckBox chkStartMenu;
        private readonly CheckBox chkDefaultProfiles;
        private readonly CheckBox chkLaunch;
        private readonly ProgressBar progressBar;
        private readonly Label lblStatus;
        private readonly Button btnInstall;
        private readonly Button btnCancel;

        private volatile bool isInstalling;

        public InstallerForm()
        {
            Text = string.Format("Instalador de {0} v{1} ({2})", AppName, AppVersion, ArchLabel);
            ClientSize = new Size(540, 385);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(24, 24, 27);
            ForeColor = Color.FromArgb(244, 244, 245);
            Font = new Font("Segoe UI", 9.5f, FontStyle.Regular);

            try
            {
                Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            }
            catch
            {
                // Ignorar si no se puede extraer el icono del ejecutable.
            }

            var lblTitle = new Label
            {
                Text = string.Format("{0} v{1} ({2})", AppName, AppVersion, ArchLabel),
                Font = new Font("Segoe UI", 16f, FontStyle.Bold),
                ForeColor = Color.White,
                Location = new Point(24, 20),
                AutoSize = true
            };

            var lblSubtitle = new Label
            {
                Text = "Emulacion de mandos DualShock 4, DualSense, Switch Pro y Joy-Con de baja latencia.",
                ForeColor = Color.FromArgb(161, 161, 170),
                Location = new Point(26, 54),
                Size = new Size(490, 22)
            };

            var lblDest = new Label
            {
                Text = "Carpeta de instalacion:",
                ForeColor = Color.FromArgb(228, 228, 231),
                Location = new Point(24, 92),
                AutoSize = true
            };

            string defaultDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Programs",
                AppName);

            txtPath = new TextBox
            {
                Text = defaultDir,
                Location = new Point(24, 116),
                Size = new Size(396, 26),
                BackColor = Color.FromArgb(39, 39, 42),
                ForeColor = Color.White,
                BorderStyle = BorderStyle.FixedSingle
            };

            btnBrowse = new Button
            {
                Text = "Examinar...",
                Location = new Point(428, 114),
                Size = new Size(88, 28),
                FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(63, 63, 70),
                ForeColor = Color.White,
                Cursor = Cursors.Hand
            };
            btnBrowse.FlatAppearance.BorderColor = Color.FromArgb(82, 82, 91);
            btnBrowse.Click += OnBrowseClick;

            chkDesktop = new CheckBox
            {
                Text = "Crear acceso directo en el Escritorio",
                Checked = true,
                Location = new Point(24, 158),
                Size = new Size(480, 24),
                ForeColor = Color.FromArgb(244, 244, 245)
            };

            chkStartMenu = new CheckBox
            {
                Text = "Crear acceso directo en el Menu Inicio",
                Checked = true,
                Location = new Point(24, 186),
                Size = new Size(480, 24),
                ForeColor = Color.FromArgb(244, 244, 245)
            };

            chkDefaultProfiles = new CheckBox
            {
                Text = "Copiar perfiles iniciales (Bateria LED y DS4 Nativo) si no existen",
                Checked = true,
                Location = new Point(24, 214),
                Size = new Size(480, 24),
                ForeColor = Color.FromArgb(244, 244, 245)
            };

            chkLaunch = new CheckBox
            {
                Text = "Iniciar ApexPad al finalizar la instalacion",
                Checked = true,
                Location = new Point(24, 242),
                Size = new Size(480, 24),
                ForeColor = Color.FromArgb(244, 244, 245)
            };

            progressBar = new ProgressBar
            {
                Location = new Point(24, 282),
                Size = new Size(492, 18),
                Minimum = 0,
                Maximum = 100,
                Value = 0
            };

            lblStatus = new Label
            {
                Text = "Listo para instalar en tu equipo.",
                ForeColor = Color.FromArgb(161, 161, 170),
                Location = new Point(24, 308),
                Size = new Size(492, 20)
            };

            btnInstall = new Button
            {
                Text = "Instalar",
                Location = new Point(316, 338),
                Size = new Size(100, 32),
                FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(0, 120, 212),
                ForeColor = Color.White,
                Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            btnInstall.FlatAppearance.BorderSize = 0;
            btnInstall.Click += OnInstallClick;

            btnCancel = new Button
            {
                Text = "Cancelar",
                Location = new Point(424, 338),
                Size = new Size(92, 32),
                FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(63, 63, 70),
                ForeColor = Color.White,
                Cursor = Cursors.Hand
            };
            btnCancel.FlatAppearance.BorderColor = Color.FromArgb(82, 82, 91);
            btnCancel.Click += delegate { Close(); };

            Controls.AddRange(new Control[]
            {
                lblTitle, lblSubtitle, lblDest, txtPath, btnBrowse,
                chkDesktop, chkStartMenu, chkDefaultProfiles, chkLaunch,
                progressBar, lblStatus, btnInstall, btnCancel
            });

            AcceptButton = btnInstall;
            CancelButton = btnCancel;
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (isInstalling)
            {
                e.Cancel = true;
                return;
            }
            base.OnFormClosing(e);
        }

        private void OnBrowseClick(object sender, EventArgs e)
        {
            using (var dlg = new FolderBrowserDialog())
            {
                dlg.Description = "Selecciona la carpeta donde deseas instalar ApexPad:";
                dlg.SelectedPath = txtPath.Text;
                if (dlg.ShowDialog(this) == DialogResult.OK && !string.IsNullOrWhiteSpace(dlg.SelectedPath))
                {
                    string selected = dlg.SelectedPath.Trim();
                    if (!selected.EndsWith(AppName, StringComparison.OrdinalIgnoreCase))
                    {
                        selected = Path.Combine(selected, AppName);
                    }
                    txtPath.Text = selected;
                }
            }
        }

        private void OnInstallClick(object sender, EventArgs e)
        {
            string targetDir = txtPath.Text.Trim();
            if (string.IsNullOrEmpty(targetDir))
            {
                MessageBox.Show(this, "Debes indicar una carpeta de destino.", AppName,
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            isInstalling = true;
            btnInstall.Enabled = false;
            btnBrowse.Enabled = false;
            btnCancel.Enabled = false;
            txtPath.Enabled = false;
            chkDesktop.Enabled = false;
            chkStartMenu.Enabled = false;
            chkDefaultProfiles.Enabled = false;
            chkLaunch.Enabled = false;

            bool createDesktop = chkDesktop.Checked;
            bool createStartMenu = chkStartMenu.Checked;
            bool copyProfiles = chkDefaultProfiles.Checked;
            bool launchAfter = chkLaunch.Checked;

            var worker = new Thread(delegate()
            {
                RunInstall(targetDir, createDesktop, createStartMenu, copyProfiles, launchAfter);
            });
            worker.IsBackground = true;
            worker.Start();
        }

        private void UpdateProgress(int percent, string message)
        {
            if (InvokeRequired)
            {
                BeginInvoke((MethodInvoker)delegate { UpdateProgress(percent, message); });
                return;
            }
            if (percent < 0) percent = 0;
            if (percent > 100) percent = 100;
            progressBar.Value = percent;
            lblStatus.Text = message;
        }

        private void RunInstall(string targetDir, bool createDesktop, bool createStartMenu, bool copyProfiles, bool launchAfter)
        {
            try
            {
                UpdateProgress(5, "Cerrando instancias activas de ApexPad...");
                StopRunningInstances();

                Directory.CreateDirectory(targetDir);
                string exePath = Path.Combine(targetDir, "ApexPad.exe");

                UpdateProgress(12, "Extrayendo archivos de ApexPad...");
                ExtractEmbeddedPayload(targetDir);

                if (copyProfiles)
                {
                    UpdateProgress(85, "Configurando perfiles iniciales...");
                    SeedAppDataProfiles(targetDir);
                }

                UpdateProgress(90, "Creando accesos directos y registro de desinstalacion...");
                if (createDesktop)
                {
                    string desktopLnk = Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                        "ApexPad.lnk");
                    CreateShortcut(desktopLnk, exePath, targetDir, "ApexPad - Emulador de mandos de baja latencia");
                }

                if (createStartMenu)
                {
                    string startFolder = Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.Programs),
                        "ApexPad");
                    Directory.CreateDirectory(startFolder);
                    CreateShortcut(
                        Path.Combine(startFolder, "ApexPad.lnk"),
                        exePath,
                        targetDir,
                        "ApexPad - Emulador de mandos de baja latencia");
                }

                string uninstallScript = WriteUninstallerScript(targetDir);
                RegisterUninstallEntry(targetDir, exePath, uninstallScript);

                UpdateProgress(100, "Instalacion completada correctamente.");

                BeginInvoke((MethodInvoker)delegate
                {
                    isInstalling = false;
                    if (launchAfter && File.Exists(exePath))
                    {
                        Process.Start(new ProcessStartInfo
                        {
                            FileName = exePath,
                            WorkingDirectory = targetDir,
                            UseShellExecute = true
                        });
                    }
                    else
                    {
                        MessageBox.Show(
                            this,
                            string.Format("ApexPad v{0} ({1}) se instalo correctamente en:\n{2}", AppVersion, ArchLabel, targetDir),
                            AppName,
                            MessageBoxButtons.OK,
                            MessageBoxIcon.Information);
                    }
                    Close();
                });
            }
            catch (Exception ex)
            {
                BeginInvoke((MethodInvoker)delegate
                {
                    isInstalling = false;
                    btnInstall.Enabled = true;
                    btnBrowse.Enabled = true;
                    btnCancel.Enabled = true;
                    txtPath.Enabled = true;
                    chkDesktop.Enabled = true;
                    chkStartMenu.Enabled = true;
                    chkDefaultProfiles.Enabled = true;
                    chkLaunch.Enabled = true;
                    lblStatus.Text = "Error durante la instalacion.";
                    MessageBox.Show(this, "No se pudo completar la instalacion:\n" + ex.Message,
                        AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
                });
            }
        }

        private static void StopRunningInstances()
        {
            Process[] procs = Process.GetProcessesByName("ApexPad");
            foreach (Process p in procs)
            {
                try
                {
                    if (!p.HasExited)
                    {
                        p.CloseMainWindow();
                        if (!p.WaitForExit(1500))
                        {
                            p.Kill();
                            p.WaitForExit(1500);
                        }
                    }
                }
                catch
                {
                    // Continuar si el proceso ya cerro o pertenece a otra sesion.
                }
                finally
                {
                    p.Dispose();
                }
            }
        }

        private void ExtractEmbeddedPayload(string targetDir)
        {
            Assembly asm = Assembly.GetExecutingAssembly();
            using (Stream stream = asm.GetManifestResourceStream(ResourceName))
            {
                if (stream == null)
                {
                    throw new InvalidOperationException("Recurso de instalacion no encontrado en el ejecutable.");
                }

                using (var archive = new ZipArchive(stream, ZipArchiveMode.Read))
                {
                    int total = archive.Entries.Count;
                    if (total == 0) total = 1;
                    int index = 0;

                    string fullRoot = Path.GetFullPath(targetDir);
                    if (!fullRoot.EndsWith(Path.DirectorySeparatorChar.ToString(), StringComparison.Ordinal))
                    {
                        fullRoot += Path.DirectorySeparatorChar;
                    }

                    foreach (ZipArchiveEntry entry in archive.Entries)
                    {
                        index++;
                        string cleanRelative = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                        string destPath = Path.GetFullPath(Path.Combine(targetDir, cleanRelative));

                        if (!destPath.StartsWith(fullRoot, StringComparison.OrdinalIgnoreCase))
                        {
                            throw new IOException("Ruta invalida en paquete de instalacion.");
                        }

                        if (string.IsNullOrEmpty(entry.Name))
                        {
                            Directory.CreateDirectory(destPath);
                            continue;
                        }

                        string parentDir = Path.GetDirectoryName(destPath);
                        if (!string.IsNullOrEmpty(parentDir))
                        {
                            Directory.CreateDirectory(parentDir);
                        }

                        // Nunca sobrescribir perfiles personalizados del usuario si ya existen.
                        bool isProfile = cleanRelative.StartsWith("Profiles" + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
                        if (isProfile && File.Exists(destPath))
                        {
                            continue;
                        }

                        entry.ExtractToFile(destPath, true);

                        if (index % 15 == 0 || index == total)
                        {
                            int pct = 15 + (int)(68.0 * index / total);
                            UpdateProgress(pct, string.Format("Extrayendo archivos ({0}/{1})...", index, total));
                        }
                    }
                }
            }
        }

        private static void SeedAppDataProfiles(string targetDir)
        {
            string sourceProfiles = Path.Combine(targetDir, "Profiles");
            if (!Directory.Exists(sourceProfiles)) return;

            string appDataProfiles = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "ApexPad",
                "Profiles");
            Directory.CreateDirectory(appDataProfiles);

            foreach (string xmlFile in Directory.GetFiles(sourceProfiles, "*.xml"))
            {
                string destFile = Path.Combine(appDataProfiles, Path.GetFileName(xmlFile));
                if (!File.Exists(destFile))
                {
                    File.Copy(xmlFile, destFile, false);
                }
            }
        }

        private static void CreateShortcut(string shortcutPath, string targetExe, string workingDir, string description)
        {
            Type shellType = Type.GetTypeFromProgID("WScript.Shell");
            if (shellType == null) return;

            object shell = Activator.CreateInstance(shellType);
            try
            {
                object shortcut = shellType.InvokeMember(
                    "CreateShortcut",
                    BindingFlags.InvokeMethod,
                    null,
                    shell,
                    new object[] { shortcutPath });

                Type shortcutType = shortcut.GetType();
                shortcutType.InvokeMember("TargetPath", BindingFlags.SetProperty, null, shortcut, new object[] { targetExe });
                shortcutType.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, shortcut, new object[] { workingDir });
                shortcutType.InvokeMember("IconLocation", BindingFlags.SetProperty, null, shortcut, new object[] { targetExe + ",0" });
                shortcutType.InvokeMember("Description", BindingFlags.SetProperty, null, shortcut, new object[] { description });
                shortcutType.InvokeMember("Save", BindingFlags.InvokeMethod, null, shortcut, null);
            }
            finally
            {
                System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shell);
            }
        }

        private static string WriteUninstallerScript(string targetDir)
        {
            string scriptPath = Path.Combine(targetDir, "Uninstall.ps1");
            string content = @"param()
Add-Type -AssemblyName System.Windows.Forms
$resp = [System.Windows.Forms.MessageBox]::Show(
    'Deseas desinstalar ApexPad de este equipo? (Tus perfiles en %APPDATA%\ApexPad se conservaran)',
    'Desinstalar ApexPad',
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)
if ($resp -ne [System.Windows.Forms.DialogResult]::Yes) { exit 0 }
Get-Process -Name 'ApexPad' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300
$desktopLnk = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'ApexPad.lnk'
$startFolder = Join-Path ([Environment]::GetFolderPath('Programs')) 'ApexPad'
Remove-Item -Path $desktopLnk -Force -ErrorAction SilentlyContinue
Remove-Item -Path $startFolder -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ApexPad' -Force -ErrorAction SilentlyContinue
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Start-Process -FilePath 'cmd.exe' -ArgumentList ""/c timeout /t 2 /nobreak >nul & rmdir /s /q `""$dir`"""" -WindowStyle Hidden
";
            File.WriteAllText(scriptPath, content, System.Text.Encoding.UTF8);
            return scriptPath;
        }

        private static void RegisterUninstallEntry(string targetDir, string exePath, string uninstallScript)
        {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\ApexPad"))
            {
                if (key == null) return;
                key.SetValue("DisplayName", string.Format("{0} ({1})", AppName, ArchLabel));
                key.SetValue("DisplayVersion", AppVersion);
                key.SetValue("Publisher", "Flavio Morales (Flavio6931)");
                key.SetValue("URLInfoAbout", "https://github.com/Flavio6931/ApexPad");
                key.SetValue("InstallLocation", targetDir);
                key.SetValue("DisplayIcon", exePath);
                key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                key.SetValue("UninstallString",
                    string.Format("powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{0}\"", uninstallScript));
            }
        }
    }
}
'@

$tempWork = Join-Path $DistDir "_installer_tmp"
New-Item -ItemType Directory -Path $tempWork -Force | Out-Null

try {
    foreach ($arch in @("x64", "x86")) {
        $sourceDir = Join-Path $DistDir "win-$arch"
        $stagingDir = Join-Path $tempWork "stage-$arch"
        $zipName = "ApexPad-v$Version-win-$arch.zip"
        $zipPath = Join-Path $DistDir $zipName
        $setupName = "ApexPad-Setup-v$Version-$arch.exe"
        $setupPath = Join-Path $DistDir $setupName

        # Empaquetamos primero el zip portable limpio.
        New-CleanPortableZip -SourceDir $sourceDir -ZipPath $zipPath -StagingDir $stagingDir

        # Generamos el codigo C# sustituyendo version y arquitectura.
        $csPath = Join-Path $tempWork "Installer-$arch.cs"
        $csContent = $installerSourceTemplate.Replace("__VERSION__", $Version).Replace("__ARCH__", $arch)
        [System.IO.File]::WriteAllText($csPath, $csContent, [System.Text.Encoding]::UTF8)

        if (Test-Path $setupPath) {
            Remove-Item -Path $setupPath -Force
        }

        Write-Host " -> Compilando $setupName..." -ForegroundColor Green
        & $cscPath `
            /nologo `
            /target:winexe `
            /optimize+ `
            /platform:$arch `
            "/win32icon:$IconPath" `
            "/out:$setupPath" `
            "/res:$zipPath,ApexPad.payload.zip" `
            /r:System.dll `
            /r:System.Core.dll `
            /r:System.Drawing.dll `
            /r:System.Windows.Forms.dll `
            /r:System.IO.Compression.dll `
            /r:System.IO.Compression.FileSystem.dll `
            $csPath

        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $setupPath)) {
            throw "Fallo la compilacion del instalador para $arch (ExitCode=$LASTEXITCODE)."
        }
    }
}
finally {
    if (Test-Path $tempWork) {
        Remove-Item -Path $tempWork -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`nPaquetes generados en $DistDir :" -ForegroundColor Green
Get-ChildItem -Path $DistDir -File | Where-Object { $_.Name -like "ApexPad*v$Version*" } |
    Select-Object Name, @{Name="MB"; Expression={[math]::Round($_.Length / 1MB, 2)}}, LastWriteTime |
    Format-Table -AutoSize
