using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Windows.Forms;

namespace LewisMDSplash
{
    [DataContract]
    internal sealed class ProgressPayload
    {
        [DataMember(Name = "state")]
        public string State { get; set; }

        [DataMember(Name = "percent")]
        public int? Percent { get; set; }

        [DataMember(Name = "message")]
        public string Message { get; set; }

        [DataMember(Name = "step")]
        public string Step { get; set; }

        [DataMember(Name = "updatedAt")]
        public string UpdatedAt { get; set; }
    }

    internal sealed class SpinnerControl : Control
    {
        private readonly Timer animationTimer;
        private int angle;
        private bool stopped;

        public SpinnerControl()
        {
            DoubleBuffered = true;
            Size = new Size(60, 60);
            animationTimer = new Timer { Interval = 80 };
            animationTimer.Tick += (_, __) =>
            {
                angle = (angle + 16) % 360;
                Invalidate();
            };
            animationTimer.Start();
        }

        public void StopAnimation()
        {
            stopped = true;
            animationTimer.Stop();
            Invalidate();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                animationTimer.Dispose();
            }

            base.Dispose(disposing);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

            var bounds = new Rectangle(8, 8, Width - 16, Height - 16);
            using (var trackPen = new Pen(Color.FromArgb(70, 255, 255, 255), 4f))
            {
                e.Graphics.DrawArc(trackPen, bounds, 0, 360);
            }

            using (var arcPen = new Pen(stopped ? Color.MistyRose : Color.White, 4f))
            {
                arcPen.StartCap = LineCap.Round;
                arcPen.EndCap = LineCap.Round;
                e.Graphics.DrawArc(arcPen, bounds, angle, 90);
            }
        }
    }

    internal sealed class SplashForm : Form
    {
        private readonly string progressFile;
        private readonly string logoPath;
        private readonly string visibleLauncherPath;
        private readonly string launcherLogPath;
        private readonly DateTime launchStartedAt = DateTime.Now;
        private readonly Timer pollTimer;
        private readonly Timer promoteTimer;
        private readonly Timer fadeTimer;
        private readonly SpinnerControl spinner;
        private readonly Label statusLabel;
        private readonly Label detailLabel;
        private readonly Label hintLabel;
        private readonly Label stepLabel;
        private readonly Label percentLabel;
        private readonly Panel progressFill;
        private readonly Button dismissButton;
        private DateTime? readyObservedAt;
        private bool closing;
        private int promotePulses;

        public SplashForm(string progressFile, string logoPath, string visibleLauncherPath, string launcherLogPath)
        {
            this.progressFile = progressFile;
            this.logoPath = logoPath;
            this.visibleLauncherPath = visibleLauncherPath;
            this.launcherLogPath = launcherLogPath;

            AutoScaleMode = AutoScaleMode.None;
            BackColor = Color.Magenta;
            ClientSize = new Size(560, 380);
            DoubleBuffered = true;
            Font = new Font("Segoe UI", 10f, FontStyle.Regular, GraphicsUnit.Point);
            FormBorderStyle = FormBorderStyle.None;
            MaximizeBox = false;
            MinimizeBox = false;
            Name = "LewisMDSplash";
            ShowIcon = false;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.CenterScreen;
            Text = "LewisMD";
            TopMost = true;
            TransparencyKey = Color.Magenta;

            var shellPanel = new Panel
            {
                Dock = DockStyle.Fill,
                BackColor = Color.Transparent,
                Padding = new Padding(28)
            };
            Controls.Add(shellPanel);

            var logo = new PictureBox
            {
                Size = new Size(120, 120),
                Location = new Point((ClientSize.Width - 120) / 2, 34),
                BackColor = Color.Transparent,
                SizeMode = PictureBoxSizeMode.Zoom
            };
            if (File.Exists(logoPath))
            {
                using (var fileStream = new FileStream(logoPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                {
                    logo.Image = Image.FromStream(fileStream);
                }
            }
            shellPanel.Controls.Add(logo);

            spinner = new SpinnerControl
            {
                Location = new Point((ClientSize.Width - 60) / 2, 144),
                BackColor = Color.Transparent
            };
            shellPanel.Controls.Add(spinner);

            var titleLabel = new Label
            {
                AutoSize = false,
                BackColor = Color.Transparent,
                ForeColor = Color.White,
                Font = new Font("Segoe UI Semibold", 24f, FontStyle.Bold, GraphicsUnit.Point),
                Text = "LewisMD",
                TextAlign = ContentAlignment.MiddleCenter,
                Bounds = new Rectangle(0, 214, ClientSize.Width, 42)
            };
            shellPanel.Controls.Add(titleLabel);

            statusLabel = new Label
            {
                AutoSize = false,
                BackColor = Color.Transparent,
                ForeColor = Color.White,
                Font = new Font("Segoe UI", 12f, FontStyle.Regular, GraphicsUnit.Point),
                Text = "Starting LewisMD...",
                TextAlign = ContentAlignment.MiddleCenter,
                Bounds = new Rectangle(90, 264, ClientSize.Width - 180, 26)
            };
            shellPanel.Controls.Add(statusLabel);

            detailLabel = new Label
            {
                AutoSize = false,
                BackColor = Color.Transparent,
                ForeColor = Color.FromArgb(214, 255, 255, 255),
                Font = new Font("Segoe UI", 10f, FontStyle.Regular, GraphicsUnit.Point),
                Text = "Preparing the local launcher",
                TextAlign = ContentAlignment.MiddleCenter,
                Bounds = new Rectangle(86, 292, ClientSize.Width - 172, 24)
            };
            shellPanel.Controls.Add(detailLabel);

            var progressTrack = new Panel
            {
                BackColor = Color.FromArgb(40, 255, 255, 255),
                Bounds = new Rectangle(42, 322, ClientSize.Width - 84, 8)
            };
            shellPanel.Controls.Add(progressTrack);

            progressFill = new Panel
            {
                BackColor = Color.White,
                Bounds = new Rectangle(0, 0, 26, 8)
            };
            progressTrack.Controls.Add(progressFill);

            stepLabel = new Label
            {
                AutoSize = false,
                BackColor = Color.Transparent,
                ForeColor = Color.FromArgb(204, 255, 255, 255),
                Font = new Font("Segoe UI", 9f, FontStyle.Regular, GraphicsUnit.Point),
                Text = "prepare",
                Bounds = new Rectangle(42, 346, 180, 18)
            };
            shellPanel.Controls.Add(stepLabel);

            percentLabel = new Label
            {
                AutoSize = false,
                BackColor = Color.Transparent,
                ForeColor = Color.White,
                Font = new Font("Segoe UI Semibold", 9f, FontStyle.Bold, GraphicsUnit.Point),
                Text = "5%",
                TextAlign = ContentAlignment.MiddleRight,
                Bounds = new Rectangle(ClientSize.Width - 142, 346, 100, 18)
            };
            shellPanel.Controls.Add(percentLabel);

            hintLabel = new Label
            {
                AutoSize = false,
                BackColor = Color.Transparent,
                ForeColor = Color.White,
                Font = new Font("Segoe UI", 9f, FontStyle.Regular, GraphicsUnit.Point),
                Visible = false,
                Bounds = new Rectangle(44, 28, ClientSize.Width - 88, 92)
            };
            shellPanel.Controls.Add(hintLabel);

            dismissButton = new Button
            {
                AutoSize = false,
                BackColor = Color.FromArgb(35, 0, 0, 0),
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Segoe UI", 9f, FontStyle.Regular, GraphicsUnit.Point),
                ForeColor = Color.White,
                Text = "Close",
                Visible = false,
                Bounds = new Rectangle((ClientSize.Width - 124) / 2, 336, 124, 34)
            };
            dismissButton.FlatAppearance.BorderColor = Color.FromArgb(70, 255, 255, 255);
            dismissButton.FlatAppearance.BorderSize = 1;
            dismissButton.Click += (_, __) => BeginClose();
            shellPanel.Controls.Add(dismissButton);

            pollTimer = new Timer { Interval = 250 };
            pollTimer.Tick += (_, __) => PollProgress();

            promoteTimer = new Timer { Interval = 500 };
            promoteTimer.Tick += (_, __) =>
            {
                promotePulses += 1;
                PromoteWindow();

                if (promotePulses >= 10)
                {
                    promoteTimer.Stop();
                }
            };

            fadeTimer = new Timer { Interval = 30 };
            fadeTimer.Tick += (_, __) =>
            {
                Opacity -= 0.14d;
                if (Opacity <= 0.05d)
                {
                    fadeTimer.Stop();
                    Close();
                }
            };

            Shown += (_, __) =>
            {
                ApplyRoundedRegion();
                PromoteWindow();
                pollTimer.Start();
                promoteTimer.Start();
                UpdateFromPayload(DefaultPayload());
                PollProgress();
            };
            Resize += (_, __) => ApplyRoundedRegion();
        }

        protected override CreateParams CreateParams
        {
            get
            {
                var parameters = base.CreateParams;
                parameters.ExStyle |= 0x00000080;
                parameters.ExStyle |= 0x00000008;
                return parameters;
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);

            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var backgroundBrush = new LinearGradientBrush(ClientRectangle,
                       ColorTranslator.FromHtml("#2D1B4E"),
                       ColorTranslator.FromHtml("#FF6B9D"),
                       30f))
            using (var path = RoundedRectangle(ClientRectangle, 26))
            {
                e.Graphics.FillPath(backgroundBrush, path);
                using (var borderPen = new Pen(Color.FromArgb(38, 255, 255, 255), 1f))
                {
                    e.Graphics.DrawPath(borderPen, path);
                }
            }
        }

        private ProgressPayload DefaultPayload()
        {
            return new ProgressPayload
            {
                State = "starting",
                Percent = 5,
                Message = "Starting LewisMD...",
                Step = "prepare"
            };
        }

        private void PollProgress()
        {
            var payload = ReadPayload() ?? DefaultPayload();
            UpdateFromPayload(payload);

            if (string.Equals(payload.State, "error", StringComparison.OrdinalIgnoreCase))
            {
                pollTimer.Stop();
                return;
            }

            if (string.Equals(payload.State, "ready", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(payload.State, "running", StringComparison.OrdinalIgnoreCase))
            {
                if (!readyObservedAt.HasValue)
                {
                    readyObservedAt = DateTime.Now;
                }
                else if ((DateTime.Now - readyObservedAt.Value).TotalMilliseconds >= 700)
                {
                    pollTimer.Stop();
                    BeginClose();
                    return;
                }
            }
            else
            {
                readyObservedAt = null;
            }

            if ((DateTime.Now - launchStartedAt).TotalSeconds >= 90)
            {
                pollTimer.Stop();
                UpdateFromPayload(new ProgressPayload
                {
                    State = "error",
                    Percent = 100,
                    Message = "LewisMD is taking longer than expected to start. You can keep waiting or open the visible launcher for details.",
                    Step = "timeout"
                });
            }
        }

        private ProgressPayload ReadPayload()
        {
            if (!File.Exists(progressFile))
            {
                return null;
            }

            try
            {
                using (var stream = new FileStream(progressFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                {
                    if (stream.Length == 0)
                    {
                        return null;
                    }

                    var serializer = new DataContractJsonSerializer(typeof(ProgressPayload));
                    var payload = serializer.ReadObject(stream) as ProgressPayload;
                    if (payload == null)
                    {
                        return null;
                    }

                    if (!string.IsNullOrWhiteSpace(payload.UpdatedAt))
                    {
                        DateTimeOffset parsedUpdatedAt;
                        if (!DateTimeOffset.TryParse(payload.UpdatedAt, out parsedUpdatedAt))
                        {
                            return null;
                        }

                        if (parsedUpdatedAt.LocalDateTime < launchStartedAt)
                        {
                            return null;
                        }
                    }

                    return payload;
                }
            }
            catch
            {
                return null;
            }
        }

        private void UpdateFromPayload(ProgressPayload payload)
        {
            var state = SafeText(payload.State, "starting");
            var percent = Math.Max(0, Math.Min(100, payload.Percent ?? 5));
            var step = SafeText(payload.Step, "prepare");
            var message = SafeText(payload.Message, "Starting LewisMD...");

            statusLabel.Text = HeadingForState(state);
            detailLabel.Text = message;
            stepLabel.Text = step;
            percentLabel.Text = percent.ToString() + "%";
            progressFill.Width = Math.Max(18, (int)Math.Round((ClientSize.Width - 84) * (percent / 100.0d)));

            if (string.Equals(state, "error", StringComparison.OrdinalIgnoreCase))
            {
                spinner.StopAnimation();
                progressFill.BackColor = Color.MistyRose;
                hintLabel.Text = HintForStep(step);
                hintLabel.Visible = true;
                dismissButton.Visible = true;
            }
            else
            {
                progressFill.BackColor = Color.White;
                hintLabel.Visible = false;
                dismissButton.Visible = false;
            }
        }

        private void BeginClose()
        {
            if (closing)
            {
                return;
            }

            closing = true;
            fadeTimer.Start();
        }

        private void PromoteWindow()
        {
            try
            {
                NativeMethods.ShowWindow(Handle, 5);
                NativeMethods.SetForegroundWindow(Handle);
                Activate();
                BringToFront();
            }
            catch
            {
            }
        }

        private void ApplyRoundedRegion()
        {
            using (var path = RoundedRectangle(ClientRectangle, 26))
            {
                Region = new Region(path);
            }
        }

        private static string SafeText(string value, string fallback)
        {
            return string.IsNullOrWhiteSpace(value) ? fallback : value;
        }

        private string HeadingForState(string state)
        {
            switch (state)
            {
                case "error":
                    return "LewisMD couldn't finish starting";
                case "ready":
                    return "LewisMD is ready";
                case "running":
                    return "LewisMD is open";
                case "stopping":
                    return "Closing LewisMD...";
                case "validation":
                    return "Validating launcher runtime";
                default:
                    return "Starting LewisMD...";
            }
        }

        private string HintForStep(string step)
        {
            if (step == "timeout")
            {
                return "LewisMD may still finish opening, but if it keeps stalling, run the visible launcher for details:\n" +
                       visibleLauncherPath + "\n\nLauncher log:\n" + launcherLogPath;
            }

            return "Open the visible launcher for details:\n" +
                   visibleLauncherPath + "\n\nLauncher log:\n" + launcherLogPath;
        }

        private static GraphicsPath RoundedRectangle(Rectangle bounds, int radius)
        {
            var diameter = radius * 2;
            var arc = new Rectangle(bounds.Location, new Size(diameter, diameter));
            var path = new GraphicsPath();

            path.AddArc(arc, 180, 90);
            arc.X = bounds.Right - diameter;
            path.AddArc(arc, 270, 90);
            arc.Y = bounds.Bottom - diameter;
            path.AddArc(arc, 0, 90);
            arc.X = bounds.Left;
            path.AddArc(arc, 90, 90);
            path.CloseFigure();

            return path;
        }
    }

    internal static class NativeMethods
    {
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }

    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            if (args.Length < 4)
            {
                return;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new SplashForm(args[0], args[1], args[2], args[3]));
        }
    }
}
