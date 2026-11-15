/*
ApexPad — Hardening Security Tests
Copyright (C) 2026 Flavio Morales
GNU General Public License v3
*/

using System;
using System.IO;
using System.Xml;
using DS4Windows;

namespace DS4WindowsTests
{
    [TestClass]
    public class SecurityHardeningTests
    {
        /// <summary>
        /// Verifica que nombres de perfil validos se resuelvan dentro de Profiles y bloquea path traversal.
        /// </summary>
        [TestMethod]
        public void TryResolveSafeProfilePath_ValidatesTraversalAndValidNames()
        {
            string tempRoot = Path.Combine(Path.GetTempPath(), $"ApexPadTest_{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path.Combine(tempRoot, "Profiles"));
            string originalAppData = Global.appdatapath;

            try
            {
                Global.appdatapath = tempRoot;
                string profilesPrefix = Path.GetFullPath(Path.Combine(tempRoot, "Profiles")) + Path.DirectorySeparatorChar;

                Assert.IsTrue(Global.TryResolveSafeProfilePath("Default", out string okPath));
                Assert.IsTrue(okPath.StartsWith(profilesPrefix, StringComparison.OrdinalIgnoreCase));
                Assert.IsTrue(okPath.EndsWith("Default.xml", StringComparison.OrdinalIgnoreCase));

                Assert.IsTrue(Global.TryResolveSafeProfilePath("FPS_Competitive 1", out string spacePath));
                Assert.IsTrue(spacePath.StartsWith(profilesPrefix, StringComparison.OrdinalIgnoreCase));

                string[] maliciousNames =
                {
                    "",
                    "   ",
                    ".",
                    "..",
                    "..\\evil",
                    "../../evil",
                    "sub\\profile",
                    "sub/profile",
                    "C:\\Windows\\System32\\calc",
                    "foo:bar",
                    "foo\0bar",
                    " Default",
                    "Default ",
                };

                foreach (string invalid in maliciousNames)
                {
                    Assert.IsFalse(Global.TryResolveSafeProfilePath(invalid, out string badPath), $"Debe rechazar: '{invalid}'");
                    Assert.AreEqual(string.Empty, badPath);
                }
            }
            finally
            {
                Global.appdatapath = originalAppData;
                if (Directory.Exists(tempRoot))
                {
                    Directory.Delete(tempRoot, true);
                }
            }
        }

        /// <summary>
        /// Verifica que CalculateFasterBT78Hash valide limites del buffer y delegue tamanos distintos a 74 bytes.
        /// </summary>
        [TestMethod]
        public void CalculateFasterBT78Hash_ValidatesBoundsAndMatchesBasicHash()
        {
            uint seed = 0x12345678u;
            int start = 0;
            int size = 10;
            byte[] nullBuffer = null;

            Assert.ThrowsException<ArgumentNullException>(() =>
                Crc32Algorithm.CalculateFasterBT78Hash(ref seed, ref nullBuffer, ref start, ref size));

            byte[] shortBuf = new byte[16];
            int badStart = -1;
            Assert.ThrowsException<ArgumentOutOfRangeException>(() =>
                Crc32Algorithm.CalculateFasterBT78Hash(ref seed, ref shortBuf, ref badStart, ref size));

            badStart = 10;
            size = 10;
            Assert.ThrowsException<ArgumentOutOfRangeException>(() =>
                Crc32Algorithm.CalculateFasterBT78Hash(ref seed, ref shortBuf, ref badStart, ref size));

            for (int i = 0; i < shortBuf.Length; i++)
            {
                shortBuf[i] = (byte)(i * 13 + 7);
            }

            start = 2;
            size = 12;
            uint s1 = 0xAABBCCDDu;
            uint s2 = 0xAABBCCDDu;
            uint fastNon74 = Crc32Algorithm.CalculateFasterBT78Hash(ref s1, ref shortBuf, ref start, ref size);
            uint basicNon74 = Crc32Algorithm.CalculateBasicHash(ref s2, ref shortBuf, start, size);
            Assert.AreEqual(basicNon74, fastNon74);

            byte[] btBuf = new byte[78];
            for (int i = 0; i < btBuf.Length; i++)
            {
                btBuf[i] = (byte)(i ^ 0x5A);
            }

            start = 0;
            size = 74;
            uint btSeed1 = 2351727372u;
            uint btSeed2 = 2351727372u;
            uint fast74 = Crc32Algorithm.CalculateFasterBT78Hash(ref btSeed1, ref btBuf, ref start, ref size);
            uint basic74 = Crc32Algorithm.CalculateBasicHash(ref btSeed2, ref btBuf, start, size);
            Assert.AreEqual(basic74, fast74);
        }

        /// <summary>
        /// Verifica que LoadXmlSafely prohíba DTD/XXE y cargue XML valido sin resolver externo.
        /// </summary>
        [TestMethod]
        public void LoadXmlSafely_BlocksDtdAndAllowsCleanXml()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), $"ApexPadXmlTest_{Guid.NewGuid():N}");
            Directory.CreateDirectory(tempDir);

            try
            {
                string xxeFile = Path.Combine(tempDir, "xxe.xml");
                File.WriteAllText(xxeFile, "<?xml version=\"1.0\"?><!DOCTYPE root [<!ENTITY test SYSTEM \"file:///C:/nonexistent\">]><DS4Windows>&test;</DS4Windows>");

                XmlDocument xxeDoc = new XmlDocument();
                Assert.ThrowsException<XmlException>(() => Global.LoadXmlSafely(xxeDoc, xxeFile));

                string validFile = Path.Combine(tempDir, "valid.xml");
                File.WriteAllText(validFile, "<DS4Windows><Color>0,0,255</Color></DS4Windows>");

                XmlDocument validDoc = new XmlDocument();
                Global.LoadXmlSafely(validDoc, validFile);
                Assert.AreEqual("0,0,255", validDoc.SelectSingleNode("/DS4Windows/Color")?.InnerText);
            }
            finally
            {
                if (Directory.Exists(tempDir))
                {
                    Directory.Delete(tempDir, true);
                }
            }
        }

        /// <summary>
        /// Verifica la busqueda segura de nodos por MAC ante entradas con metacaracteres XPath.
        /// </summary>
        [TestMethod]
        public void FindControllerNodeByMac_IgnoresXPathInjectionCharacters()
        {
            XmlDocument doc = new XmlDocument();
            doc.LoadXml("<Controllers><Controller Mac=\"AA:BB:CC:DD:EE:FF\" /></Controllers>");

            XmlNode found = Global.FindControllerNodeByMac(doc, "aa:bb:cc:dd:ee:ff");
            Assert.IsNotNull(found);

            XmlNode missing = Global.FindControllerNodeByMac(doc, "\"] | //* | //Controller[@Mac=\"");
            Assert.IsNull(missing);
        }

        /// <summary>
        /// Verifica el filtrado de esquemas URI y destinos seguros en Util.
        /// </summary>
        [TestMethod]
        public void UtilShellValidation_AllowsHttpsAndBlocksUnsafeTargets()
        {
            Assert.IsTrue(Util.IsAllowedWebUri("https://github.com/Flavio6931/ApexPad"));
            Assert.IsTrue(Util.IsAllowedWebUri("http://localhost:8080/health"));

            Assert.IsFalse(Util.IsAllowedWebUri("ms-msdt:/id PCWDiagnostic"));
            Assert.IsFalse(Util.IsAllowedWebUri("javascript:alert(1)"));
            Assert.IsFalse(Util.IsAllowedWebUri("file:///C:/Windows/System32/cmd.exe"));
            Assert.IsFalse(Util.IsAllowedWebUri("https://example.com\" --gpu-launcher=calc"));

            Assert.IsFalse(Util.IsAllowedShellTarget("cmd.exe"));
            Assert.IsFalse(Util.IsAllowedShellTarget(@"\\attacker\share\evil.exe"));
            Assert.IsFalse(Util.IsAllowedShellTarget(@"file:///C:/Windows/System32/cmd.exe"));

            string tempDir = Path.Combine(Path.GetTempPath(), $"ApexPadDir_{Guid.NewGuid():N}");
            Directory.CreateDirectory(tempDir);
            try
            {
                Assert.IsTrue(Util.IsAllowedShellTarget(tempDir));
            }
            finally
            {
                Directory.Delete(tempDir, true);
            }
        }
    }
}
