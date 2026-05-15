@{
    Severity     = @('Warning', 'Error')
    ExcludeRules = @(
        # Write-Host ist in diesen interaktiven Console-Skripten intentionell
        # (farbige Ausgabe). Ab PS 5.0 schreibt Write-Host in den Information-Stream.
        'PSAvoidUsingWriteHost',

        # BOM-Kodierung wird separat sichergestellt (UTF-8 ohne BOM fuer PS 5.1-Kompatibilitaet).
        'PSUseBOMForUnicodeEncodedFile',

        # Leere catch-Bloecke sind hier intentionell (optionale JSON-Dateien werden ignoriert).
        'PSAvoidUsingEmptyCatchBlock'
    )
}
