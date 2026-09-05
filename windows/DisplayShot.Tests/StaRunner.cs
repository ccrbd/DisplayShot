namespace DisplayShot.Tests;

/// <summary>Runs a test body on an STA thread. WPF's RenderTargetBitmap requires STA even headless.</summary>
public static class StaRunner
{
    public static void Run(Action body)
    {
        Exception? captured = null;
        var thread = new Thread(() =>
        {
            try { body(); }
            catch (Exception ex) { captured = ex; }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (captured is not null) throw captured;
    }
}
