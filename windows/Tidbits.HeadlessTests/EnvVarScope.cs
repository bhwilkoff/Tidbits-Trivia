namespace Tidbits.HeadlessTests;

/// Deterministically sets a process-wide environment variable for the lifetime of the
/// scope and restores the PRIOR value on Dispose — even if the test body throws (an
/// assertion failure). Pairs with the "EnvSensitive" xUnit collection: serialization stops
/// two tests from touching `TIDBITS_CLUB` at the same time, and this stops a single test
/// from leaking its value past its own run.
internal sealed class EnvVarScope : IDisposable
{
    private readonly string _name;
    private readonly string? _previous;

    public EnvVarScope(string name, string? value)
    {
        _name = name;
        _previous = Environment.GetEnvironmentVariable(name);
        Environment.SetEnvironmentVariable(name, value);
    }

    public void Dispose() => Environment.SetEnvironmentVariable(_name, _previous);
}
