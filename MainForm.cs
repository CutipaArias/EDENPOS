using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Windows.Forms;

namespace EdenPOS
{
    public sealed class MainForm : Form
    {
        private readonly Panel sidebar;
        private readonly Panel host;
        private readonly Label employeeLabel;
        private readonly Label storeLabel;
        private readonly Pill rolePill;
        private readonly Dictionary<string, NavButton> navButtons = new Dictionary<string, NavButton>();
        private readonly Dictionary<string, Control> views = new Dictionary<string, Control>();
        private string currentKey;
        public bool LogoutRequested { get; private set; }
        private DataRevisionPoller revisionPoller;   // sondeo en segundo plano de cambios hechos por otras cajas
        private bool remoteRefreshQueued;

        // Cierra la ventana principal y vuelve al inicio de sesión (p. ej. si una restauración eliminó al usuario de la sesión).
        public void ForceLogout()
        {
            LogoutRequested = true;
            Close();
        }

        public MainForm()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            Text = "Edén POS";
            try { Icon = System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
            StartPosition = FormStartPosition.CenterScreen;
            WindowState = FormWindowState.Maximized;
            MinimumSize = new Size(800, 600);
            AutoScaleMode = AutoScaleMode.Dpi;
            BackColor = Theme.Canvas;
            Font = Theme.Body;
            KeyPreview = true;

            // El área de contenido es el lienzo (Canvas): cada vista pone su ScreenHeader encima, sin franja verde propia de MainForm.
            sidebar = new Panel { Dock = DockStyle.Left, Width = 232, BackColor = Theme.SidebarBack, Padding = new Padding(0) };
            host = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Canvas };
            Controls.Add(host);
            Controls.Add(sidebar);

            var sidebarLayout = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 1,
                RowCount = 3,
                BackColor = Theme.SidebarBack,
                Margin = new Padding(0),
                Padding = new Padding(0)
            };
            sidebarLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
            sidebarLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 136f));
            sidebarLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
            sidebarLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 104f));
            sidebar.Controls.Add(sidebarLayout);

            // Identidad: negocio arriba, debajo el usuario y su rol en una Pill.
            var brand = new Panel { Dock = DockStyle.Fill, BackColor = Theme.SidebarBack, Padding = new Padding(Theme.Space.Xl, Theme.Space.Xl, Theme.Space.Lg, Theme.Space.Md), Margin = new Padding(0) };
            storeLabel = new Label
            {
                Dock = DockStyle.Top,
                Height = 28,
                ForeColor = SidebarWhite,
                Font = Theme.Subhead,
                TextAlign = ContentAlignment.MiddleLeft,
                AutoEllipsis = true,
                BackColor = Theme.SidebarBack
            };
            employeeLabel = new Label
            {
                Dock = DockStyle.Top,
                Height = 28,
                ForeColor = Theme.SidebarText,
                Font = Theme.Body,
                TextAlign = ContentAlignment.BottomLeft,
                AutoEllipsis = true,
                BackColor = Theme.SidebarBack
            };
            var roleHost = new Panel { Dock = DockStyle.Top, Height = 34, BackColor = Theme.SidebarBack, Padding = new Padding(0, Theme.Space.Sm, 0, 0) };
            rolePill = Theme.Pill("", Tone.Brand);
            rolePill.Location = new Point(0, Theme.Space.Sm);
            roleHost.Controls.Add(rolePill);
            brand.Controls.Add(roleHost);
            brand.Controls.Add(employeeLabel);
            brand.Controls.Add(storeLabel);
            sidebarLayout.Controls.Add(brand, 0, 0);

            // Pie: versión y "Cerrar sesión" como acción secundaria.
            var footer = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 1,
                RowCount = 2,
                BackColor = Theme.SidebarBack,
                Margin = new Padding(0),
                Padding = new Padding(Theme.Space.Lg, Theme.Space.Xs, Theme.Space.Lg, Theme.Space.Lg)
            };
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
            footer.RowStyles.Add(new RowStyle(SizeType.Absolute, 28f));
            footer.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
            footer.Controls.Add(new Label
            {
                Text = "Edén POS  ·  v2.3.1",
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.MiddleLeft,
                ForeColor = Theme.SidebarMuted,
                Font = Theme.Caption,
                BackColor = Theme.SidebarBack
            }, 0, 0);
            var logout = Theme.Button("Cerrar sesión", ButtonVariant.Ghost);
            logout.Dock = DockStyle.Fill;
            logout.Margin = new Padding(0);
            logout.ForeColor = Theme.SidebarText;
            logout.FlatAppearance.BorderColor = Theme.SidebarActive;
            logout.FlatAppearance.MouseOverBackColor = Theme.SidebarHover;
            logout.FlatAppearance.MouseDownBackColor = Theme.SidebarActive;
            logout.Click += (s, e) =>
            {
                if (MessageBox.Show("¿Cerrar la sesión de " + AppSession.UserName + "?", "Cerrar sesión", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
                LogoutRequested = true;
                Close();
            };
            footer.Controls.Add(logout, 0, 1);
            sidebarLayout.Controls.Add(footer, 0, 2);

            var navigation = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.TopDown,
                WrapContents = false,
                AutoScroll = true,
                BackColor = Theme.SidebarBack,
                Padding = new Padding(Theme.Space.Md, Theme.Space.Sm, Theme.Space.Md, 0)
            };
            sidebarLayout.Controls.Add(navigation, 0, 1);

            if (AppSession.IsOwner)
            {
                AddNavigation(navigation, "inventory", "", "Inventario", null, () => new ProductsView());
                AddNavigation(navigation, "reports", "", "Reportes", null, () => new ReportsView());
                AddNavigation(navigation, "audit", "", "Auditoría", null, () => new AuditView());
                AddNavigation(navigation, "settings", "", "Configuración", null, () => new SettingsView());
            }
            else
            {
                AddNavigation(navigation, "sales", "", "Ventas", "F2", () => new SalesView());
                AddNavigation(navigation, "receipts", "", "Recibos", "F3", () => new ReceiptsView());
                AddNavigation(navigation, "shift", "", "Turno", "F4", () => new ShiftView());
            }

            var updatingLayout = false;
            Action updateResponsiveLayout = () =>
            {
                if (updatingLayout) return;
                updatingLayout = true;
                try
                {
                    var dpiScale = Math.Max(1f, DeviceDpi / 96f);
                    var minimumSidebar = (int)Math.Round(180 * dpiScale);
                    var maximumSidebar = (int)Math.Round(300 * dpiScale);
                    sidebar.Width = Math.Max(minimumSidebar, Math.Min(maximumSidebar, (int)(ClientSize.Width * 0.17)));
                    // El cambio de ancho ocurre dentro del layout de la ventana y WinForms aplaza el de la barra: sin esto el
                    // contenido de la barra se quedaba con el ancho anterior (botones más estrechos que la barra).
                    sidebar.PerformLayout();
                    sidebarLayout.PerformLayout();
                    foreach (var button in navButtons.Values)
                        button.Width = Math.Max(150, navigation.ClientSize.Width - navigation.Padding.Horizontal);
                }
                finally { updatingLayout = false; }
            };
            Resize += (s, e) => updateResponsiveLayout();
            navigation.SizeChanged += (s, e) => updateResponsiveLayout();

            AppData.DataChanged += OnDataChanged;
            revisionPoller = new DataRevisionPoller(OnRemoteRevisionChanged, 5000);
            FormClosed += (s, e) =>
            {
                AppData.DataChanged -= OnDataChanged;
                var poller = revisionPoller;
                revisionPoller = null;
                if (poller != null) poller.Dispose();
                host.Controls.Clear();
                foreach (var view in views.Values.ToList()) view.Dispose();   // todas las vistas cacheadas (se desuscriben de AppData)
                views.Clear();
            };
            KeyDown += MainForm_KeyDown;
            UpdateIdentity();
            updateResponsiveLayout();
            Navigate(AppSession.IsOwner ? "inventory" : "sales");
        }

        private static readonly Color SidebarWhite = Color.White;   // blanco sobre SidebarBack

        private void AddNavigation(FlowLayoutPanel navigation, string key, string glyph, string text, string hint, Func<Control> factory)
        {
            var button = new NavButton(glyph, text, hint) { Width = 200, Tag = factory };
            button.Click += (s, e) => Navigate(key);
            navigation.Controls.Add(button);
            navButtons[key] = button;
        }

        private void Navigate(string key)
        {
            if (!navButtons.ContainsKey(key)) return;
            currentKey = key;
            foreach (var item in navButtons) item.Value.Active = item.Key == key;

            if (!views.ContainsKey(key))
            {
                var factory = (Func<Control>)navButtons[key].Tag;
                var control = factory();
                control.Dock = DockStyle.Fill;
                views[key] = control;
            }

            host.SuspendLayout();
            host.Controls.Clear();
            host.Controls.Add(views[key]);
            host.ResumeLayout();
            var refreshable = views[key] as IRefreshable;
            if (refreshable != null) refreshable.RefreshView();
        }

        private void UpdateIdentity(bool automatic = false)
        {
            AppSettings settings;
            try
            {
                settings = AppData.Settings;
            }
            catch (MySqlConnector.MySqlException ex)
            {
                AppData.LogError(ex, "Identidad (base de datos)");
                if (automatic) return;   // refresco automático: se registra y se sigue, sin ventana modal
                Theme.Message(this, Tone.Danger, AppData.DescribeDatabaseError(ex));
                return;
            }
            employeeLabel.Text = string.IsNullOrWhiteSpace(AppSession.UserName) ? settings.EmployeeName : AppSession.UserName;
            rolePill.Text = AppSession.RoleName;
            storeLabel.Text = settings.StoreName;
            Text = "Edén POS — " + settings.StoreName;
        }

        private void OnDataChanged(object sender, EventArgs e)
        {
            var poller = revisionPoller;
            if (poller != null) poller.NotifyLocalChange();   // cambio de esta caja: no se vuelve a refrescar al detectarlo el sondeo
            if (!IsHandleCreated || IsDisposed) return;
            if (InvokeRequired)
            {
                try { BeginInvoke(new Action(UpdateCurrentView)); }
                catch (ObjectDisposedException) { }
                catch (InvalidOperationException) { }
                return;
            }
            UpdateCurrentView();
        }

        // Hilo de fondo: otra caja cambió datos. Solo se pasa a la UI; nada de MySQL aquí.
        private void OnRemoteRevisionChanged(string revision)
        {
            if (!IsHandleCreated || IsDisposed) return;
            if (remoteRefreshQueued) return;
            remoteRefreshQueued = true;
            try { BeginInvoke(new Action(() => { remoteRefreshQueued = false; ApplyRemoteChange(revision); })); }
            catch (ObjectDisposedException) { remoteRefreshQueued = false; }
            catch (InvalidOperationException) { remoteRefreshQueued = false; }
        }

        // Hilo de la UI. Si no es buen momento (diálogo abierto, Configuración, edición) no se acepta la revisión:
        // el siguiente sondeo (5 s) la vuelve a detectar y reintenta. No muestra mensajes.
        private void ApplyRemoteChange(string revision)
        {
            if (IsDisposed || !IsHandleCreated || revisionPoller == null) return;
            if (!CanRefreshForRemoteChange()) return;
            try { UpdateCurrentView(true); }
            catch (Exception ex) { AppData.LogError(ex, "Actualización por cambios de otra caja"); }
            if (revisionPoller != null) revisionPoller.Accept(revision);
        }

        private bool CanRefreshForRemoteChange()
        {
            if (currentKey == null || currentKey == "settings") return false;   // Configuración no se pisa mientras se escribe
            // Reportes y Auditoría son consultas pesadas y la usuaria filtra a mano: no se relanzan solas en el hilo de la interfaz.
            if (currentKey == "reports" || currentKey == "audit") return false;
            if (!Enabled || WindowState == FormWindowState.Minimized) return false;   // MessageBox/diálogo modal deshabilita el formulario
            foreach (Form form in Application.OpenForms)
                if (form != this && form.Visible && form.Modal) return false;
            // Ventas conserva carrito y ticket en curso al refrescar (RenderCart repinta el carrito en memoria): se refresca aunque haya foco en un cuadro de texto.
            // Las demás vistas reconstruyen sus controles: no se refrescan mientras haya un editor con foco.
            if (currentKey != "sales" && IsEditorFocused()) return false;
            return true;
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern IntPtr GetFocus();

        private static bool IsEditorFocused()
        {
            Control focused;
            try { focused = Control.FromHandle(GetFocus()); }
            catch { return false; }
            if (focused == null) return false;
            if (focused is TextBoxBase || focused is NumericUpDown || focused is DateTimePicker) return true;
            var combo = focused as ComboBox;
            if (combo != null) return combo.DroppedDown || combo.DropDownStyle != ComboBoxStyle.DropDownList;
            var grid = focused as DataGridView;
            if (grid != null) return grid.IsCurrentCellInEditMode;
            return false;
        }

        private void UpdateCurrentView() { UpdateCurrentView(false); }

        private void UpdateCurrentView(bool automatic)
        {
            UpdateIdentity(automatic);
            Control control;
            if (currentKey != null && views.TryGetValue(currentKey, out control))
            {
                var refreshable = control as IRefreshable;
                if (refreshable != null) refreshable.RefreshView();
            }
        }

        private void MainForm_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.F2) Navigate("sales");
            else if (e.KeyCode == Keys.F3) Navigate("receipts");
            else if (e.KeyCode == Keys.F4) Navigate("shift");
            else if (e.KeyCode == Keys.F5) UpdateCurrentView();
        }

        // Elemento de navegación de la barra lateral: píldora SidebarActive + indicador verde de marca cuando está activo.
        private sealed class NavButton : Button
        {
            private readonly string glyph, label, hint;
            private bool hover, pressed, active;
            private static readonly Font IconFont = CreateIconFont();

            public NavButton(string glyph, string label, string hint)
            {
                this.glyph = glyph; this.label = label; this.hint = hint;
                SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
                FlatStyle = FlatStyle.Flat;
                FlatAppearance.BorderSize = 0;
                UseVisualStyleBackColor = false;
                Height = 46;
                Margin = new Padding(0, 0, 0, Theme.Space.Xs);
                Cursor = Cursors.Hand;
                Font = Theme.Body;
                BackColor = Theme.SidebarBack;
                AccessibleName = label;
            }

            public bool Active { get { return active; } set { active = value; Invalidate(); } }

            private static Font CreateIconFont()
            {
                using (var probe = new System.Drawing.Text.InstalledFontCollection())
                {
                    foreach (var family in new[] { "Segoe Fluent Icons", "Segoe MDL2 Assets" })
                        if (probe.Families.Any(f => f.Name == family)) return new Font(family, 13f, FontStyle.Regular, GraphicsUnit.Point);
                }
                return null;
            }

            // Button (ButtonBase) activa ControlStyles.Opaque: Windows Forms NUNCA llama a OnPaintBackground en WM_PAINT. Con
            // OptimizedDoubleBuffer el búfer es compartido por todos los controles, así que si OnPaint no pinta su fondo quedan
            // los píxeles del último control pintado (otro NavButton: textos encimados y fondo "activo" en todos).
            // Por eso el fondo completo se pinta aquí, al inicio de OnPaint.
            protected override void OnPaintBackground(PaintEventArgs e) { }

            protected override void OnPaint(PaintEventArgs e)
            {
                var g = e.Graphics;
                g.Clear(Theme.SidebarBack);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                var rect = new Rectangle(0, 0, Width - 1, Height - 1);
                var fill = pressed ? Theme.SidebarActive : active ? Theme.SidebarActive : hover ? Theme.SidebarHover : Theme.SidebarBack;
                if (pressed && !active) fill = Theme.Blend(Theme.SidebarHover, Theme.SidebarActive, 0.6);
                if (fill != Theme.SidebarBack)
                    using (var path = Gfx.Round(rect, Theme.Radius.Control + 2))
                    using (var brush = new SolidBrush(fill)) g.FillPath(brush, path);

                if (active)
                    using (var path = Gfx.Round(new Rectangle(0, (Height - 22) / 2, 4, 22), 2))
                    using (var brush = new SolidBrush(Theme.Green)) g.FillPath(brush, path);

                var textColor = active ? Color.White : Theme.SidebarText;
                const int iconLeft = Theme.Space.Lg;
                var textLeft = iconLeft + 36;
                if (IconFont != null)
                    TextRenderer.DrawText(g, glyph, IconFont, new Rectangle(iconLeft, 0, 28, Height), active ? Color.White : Theme.SidebarMuted,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
                else textLeft = iconLeft;
                var hintWidth = string.IsNullOrEmpty(hint) ? 0 : 36;
                TextRenderer.DrawText(g, label, active ? Theme.Subhead : Theme.Body, new Rectangle(textLeft, 0, Math.Max(0, Width - textLeft - hintWidth - Theme.Space.Sm), Height), textColor,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine);
                if (hintWidth > 0)
                    TextRenderer.DrawText(g, hint, Theme.Caption, new Rectangle(Width - hintWidth - Theme.Space.Md, 0, hintWidth, Height), Theme.SidebarMuted,
                        TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine);

                if (Focused && ShowFocusCues)
                    using (var path = Gfx.Round(new Rectangle(1, 1, Width - 3, Height - 3), Theme.Radius.Control + 1))
                    using (var pen = new Pen(Theme.SidebarMuted, 1.5f)) g.DrawPath(pen, path);
            }

            protected override void OnMouseDown(MouseEventArgs mevent)
            {
                if (mevent.Button == MouseButtons.Left) { pressed = true; Invalidate(); Update(); }   // respuesta al presionar, no al soltar
                base.OnMouseDown(mevent);
            }
            protected override void OnMouseUp(MouseEventArgs mevent) { pressed = false; Invalidate(); base.OnMouseUp(mevent); }
            protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
            protected override void OnMouseLeave(EventArgs e) { hover = false; if (!Capture) pressed = false; Invalidate(); base.OnMouseLeave(e); }
            protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
            protected override void OnLostFocus(EventArgs e) { pressed = false; Invalidate(); base.OnLostFocus(e); }
        }
    }
}
