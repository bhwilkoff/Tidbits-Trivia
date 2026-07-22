namespace Tidbits.HeadlessTests;

/// Marker collection for tests that read or write the process-wide `TIDBITS_CLUB` env var
/// (`DebugHooks.ForceClub`, see Tidbits.Core/Store/GameTypes.cs). xUnit runs different test
/// collections IN PARALLEL by default; a plain [Fact] class and an [AvaloniaFact] snapshot
/// class are two different collections unless both opt into this one, so a set in one could
/// be read (or clobbered) by the other mid-test. `DisableParallelization = true` forces every
/// class tagged [Collection("EnvSensitive")] to run one at a time, in isolation from each
/// other — the env var is process-wide, so nothing less than serialization is safe.
[CollectionDefinition("EnvSensitive", DisableParallelization = true)]
public class EnvSensitiveCollection;
