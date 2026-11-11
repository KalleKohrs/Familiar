import FamiliarCore

/// Macht aus einer Anfrage ein `Result`, damit der Fehlertyp erhalten bleibt: `async let` meldet Fehler
/// sonst nur als `any Error`, und die Stores arbeiten mit `FamiliarError`.
///
/// Gebrauch für gleichzeitige Anfragen:
/// ```
/// async let a = captured { try await repository.eins() }
/// async let b = captured { try await repository.zwei() }
/// let (ra, rb) = await (a, b)
/// let (x, y) = (try ra.get(), try rb.get())
/// ```
func captured<T>(_ work: () async throws(FamiliarError) -> T) async -> Result<T, FamiliarError> {
    do throws(FamiliarError) {
        return .success(try await work())
    } catch {
        return .failure(error)
    }
}
