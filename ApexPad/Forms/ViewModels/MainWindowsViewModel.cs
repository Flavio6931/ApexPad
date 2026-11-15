/*
DS4Windows
Copyright (C) 2023  Travis Nickles

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

using DS4Windows;
using DS4WinWPF.ApiDTO;
using HttpProgress;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net.Http.Json;
using System.Threading.Tasks;

namespace DS4WinWPF.DS4Forms.ViewModels
{
    public class MainWindowsViewModel
    {
        private bool fullTabsEnabled = true;

        public bool FullTabsEnabled
        {
            get => fullTabsEnabled;
            set
            {
                fullTabsEnabled = value;
                FullTabsEnabledChanged?.Invoke(this, EventArgs.Empty);
            }
        }
        public event EventHandler FullTabsEnabledChanged;

        public string updaterExe = Environment.Is64BitProcess ? "DS4Updater.exe" : "DS4Updater_x86.exe";

        /// <summary>
        /// Actualizador externo heredado deshabilitado por seguridad; devuelve vacio.
        /// </summary>
        private string DownloadUpstreamUpdaterVersion()
        {
            return string.Empty;
        }

        /// <summary>
        /// Comprobacion automatica de actualizador heredado deshabilitada por seguridad.
        /// </summary>
        public bool RunUpdaterCheck(bool launch, out string upstreamVersion)
        {
            upstreamVersion = string.Empty;
            return false;
        }

        /// <summary>
        /// Consulta automatica de version heredada deshabilitada por seguridad.
        /// </summary>
        public void DownloadUpstreamVersionInfo()
        {
        }

        public void CheckDrivers()
        {
            bool deriverinstalled = Global.IsViGEmBusInstalled();
            if (!deriverinstalled || !Global.IsRunningSupportedViGEmBus())
            {
                ProcessStartInfo startInfo = new ProcessStartInfo();
                startInfo.FileName = $"{Global.exelocation}";
                startInfo.Arguments = "-driverinstall";
                startInfo.Verb = "runas";
                startInfo.UseShellExecute = true;
                try
                {
                    using (Process temp = Process.Start(startInfo))
                    {
                    }
                }
                catch { }
            }
        }

        /// <summary>
        /// Ejecucion de DS4Updater deshabilitada por seguridad.
        /// </summary>
        public bool LauchDS4Updater()
        {
            return false;
        }

        public bool IsNET8Available()
        {
            return DS4Windows.Util.IsNet8DesktopRuntimeAvailable();
        }
    }
}
