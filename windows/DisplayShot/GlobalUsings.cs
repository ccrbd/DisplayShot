// This project enables both WPF (UseWPF) and WinForms (UseWindowsForms, for the tray NotifyIcon).
// That pulls System.Drawing and System.Windows.Forms into scope alongside System.Windows, making
// many simple type names ambiguous. These aliases pin every shared name to its WPF meaning; the few
// WinForms/GDI types we need (in Tray and Capture) are referenced by their full names there.
global using Application = System.Windows.Application;
global using Brush = System.Windows.Media.Brush;
global using Button = System.Windows.Controls.Button;
global using Clipboard = System.Windows.Clipboard;
global using Color = System.Windows.Media.Color;
global using FlowDirection = System.Windows.FlowDirection;
global using FontFamily = System.Windows.Media.FontFamily;
global using Brushes = System.Windows.Media.Brushes;
global using Control = System.Windows.Controls.Control;
global using Cursor = System.Windows.Input.Cursor;
global using Cursors = System.Windows.Input.Cursors;
global using DataObject = System.Windows.DataObject;
global using HorizontalAlignment = System.Windows.HorizontalAlignment;
global using KeyEventArgs = System.Windows.Input.KeyEventArgs;
global using MessageBox = System.Windows.MessageBox;
global using MouseEventArgs = System.Windows.Input.MouseEventArgs;
global using Orientation = System.Windows.Controls.Orientation;
global using Pen = System.Windows.Media.Pen;
global using Point = System.Windows.Point;
global using Size = System.Windows.Size;
global using TextBox = System.Windows.Controls.TextBox;
global using VerticalAlignment = System.Windows.VerticalAlignment;
