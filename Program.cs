using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows.Forms;

namespace EdenPOS
{
    internal static class Program
    {
        // Importa desde DataDirectory y muestra el resumen. false si falló (no se importó nada: la transacción se revierte).
        private static bool ImportLegacyJson()
        {
            try
            {
                var summary = AppData.ImportLegacyJson(AppData.DataDirectory);
                MessageBox.Show("Importación completada.\n\n" + summary.ToText(), "Edén POS", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return true;
            }
            catch (Exception ex)
            {
                AppData.LogError(ex, "Importación de datos antiguos");
                var detail = ex is MySqlConnector.MySqlException ? AppData.DescribeDatabaseError((MySqlConnector.MySqlException)ex) : ex.Message;
                MessageBox.Show(
                    "No se pudieron importar los datos antiguos: " + detail + "\n\nNo se guardó nada en la base de datos y los archivos originales no se modificaron.",
                    "Error de importación", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false;
            }
        }

        private static void RunMigrateJson()
        {
            if (AppData.HasBusinessData())
            {
                MessageBox.Show(
                    "La base de datos ya tiene datos de negocio, así que no se importó nada. La importación de los JSON antiguos solo se hace con la base vacía, para no mezclar ni duplicar información.",
                    "Edén POS", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            if (!AppData.HasLegacyJsonFiles(AppData.DataDirectory))
            {
                MessageBox.Show("No se encontraron datos antiguos (JSON) en:\n" + AppData.DataDirectory, "Edén POS", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            ImportLegacyJson();
        }

        [STAThread]
        private static void Main(string[] args)
        {
            var culture = new CultureInfo("es-PE");
            Thread.CurrentThread.CurrentCulture = culture;
            Thread.CurrentThread.CurrentUICulture = culture;
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);

            try
            {
                // Comprobar MySQL antes de inicializar: muestra un mensaje claro sin exponer la cadena de conexión.
                string databaseError;
                if (!SqlConnectionFactory.TryPing(out databaseError))
                {
                    AppData.LogError(new InvalidOperationException(databaseError), "Arranque: base de datos no disponible");
                    MessageBox.Show(
                        "No se pudo iniciar Edén POS.\n\n" + databaseError,
                        "Error de inicio",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                    return;
                }
                // --migrate-json: importación única de los JSON antiguos; no abre la aplicación.
                if (args != null && args.Any(x => string.Equals(x, "--migrate-json", StringComparison.OrdinalIgnoreCase)))
                {
                    RunMigrateJson();
                    return;
                }
                // Base vacía + JSON antiguos en la carpeta de datos: se ofrece importarlos ANTES de las siembras por defecto de Initialize.
                if (AppData.HasLegacyJsonToImport())
                {
                    var answer = MessageBox.Show(
                        "Se encontraron datos de la versión anterior. ¿Desea importarlos a la nueva base de datos? Los archivos originales no se modifican.",
                        "Edén POS", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                    if (answer == DialogResult.Yes && !ImportLegacyJson()) return;
                }
                AppData.Initialize();
                // Reintento de comprobantes simulados (cada 5 min mientras la app esté abierta). Se detiene al salir.
                ElectronicInvoicingService.Start();
                // Copia automática diaria a la carpeta elegida (si está activada); comprueba cada 30 min en segundo plano.
                AppData.StartAutoBackupScheduler();
                // Réplica en Supabase (si está activada en esta PC): sube en segundo plano solo lo que cambia.
                AppData.StartSupabaseReplica();
                Application.ThreadException += (s, e) =>
                {
                    AppData.LogError(e.Exception, "Error no controlado de interfaz");
                    MessageBox.Show("Ocurrió un error inesperado. El detalle se guardó en errors.log.", "Edén POS", MessageBoxButtons.OK, MessageBoxIcon.Error);
                };
                AppDomain.CurrentDomain.UnhandledException += (s, e) => AppData.LogError(e.ExceptionObject as Exception, "Error no controlado de aplicación");
                while (true)
                {
                    using (var login = new LoginForm())
                    {
                        if (login.ShowDialog() != DialogResult.OK) break;
                    }

                    bool returnToLogin;
                    using (var main = new MainForm())
                    {
                        Application.Run(main);
                        returnToLogin = main.LogoutRequested;
                    }
                    AppSession.SignOut();
                    if (!returnToLogin) break;
                }
                ElectronicInvoicingService.Stop();
                AppData.StopAutoBackupScheduler();
                AppData.StopSupabaseReplica();
            }
            catch (MySqlConnector.MySqlException ex)
            {
                AppData.LogError(ex, "Error de inicio (base de datos)");
                MessageBox.Show(
                    "No se pudo iniciar Edén POS.\n\n" + AppData.DescribeDatabaseError(ex),
                    "Error de inicio",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            catch (Exception ex)
            {
                AppData.LogError(ex, "Error de inicio");
                MessageBox.Show(
                    "No se pudo iniciar Edén POS.\n\n" + ex.Message,
                    "Error de inicio",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
        }
    }
}
