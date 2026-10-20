# Helpers used by scripts\compile.ps1. Kept apart so tests\Compile.Tests.ps1 can load them.

function Read-UTSourceFile {
    param([Parameter(Mandatory)][string]$Path)
    # Source files are UTF-8 (with BOM, required by PowerShell 5.1 when they contain accents).
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

function ConvertTo-UTAsciiJson {
    param([Parameter(Mandatory)][string]$Text)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        if ([int]$ch -gt 127) { [void]$sb.AppendFormat('\u{0:x4}', [int]$ch) } else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

function ConvertTo-UTAsciiXml {
    param([Parameter(Mandatory)][string]$Text)
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $Text.Length) {
        $ch = $Text[$i]
        if ([char]::IsHighSurrogate($ch) -and ($i + 1) -lt $Text.Length) {
            [void]$sb.AppendFormat('&#x{0:X};', [char]::ConvertToUtf32($ch, $Text[$i + 1]))
            $i += 2
            continue
        }
        if ([int]$ch -gt 127) { [void]$sb.AppendFormat('&#x{0:X};', [int]$ch) } else { [void]$sb.Append($ch) }
        $i++
    }
    return $sb.ToString()
}

function ConvertTo-UTFoldedAscii {
    # For comments only: strip diacritics, replace anything left with '?'.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $normalized.ToCharArray()) {
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($category -eq [Globalization.UnicodeCategory]::NonSpacingMark) { continue }
        if ([int]$ch -gt 127) { [void]$sb.Append('?') } else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

function ConvertTo-UTExpandableEscape {
    # Escapes literal text so it can live inside a double-quoted PowerShell string.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [switch]$HereString)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        if ($code -gt 127) { [void]$sb.AppendFormat('$([char]0x{0:X4})', $code); continue }
        switch -CaseSensitive ([string]$ch) {
            '`' { [void]$sb.Append('``') }
            '$' { [void]$sb.Append('`$') }
            '"' { if ($HereString) { [void]$sb.Append('"') } else { [void]$sb.Append('`"') } }
            default {
                # Typographic quotes also open/close strings in PowerShell; they are > 127 so never here.
                [void]$sb.Append($ch)
            }
        }
    }
    return $sb.ToString()
}

function Test-UTHasNonAscii {
    param([AllowEmptyString()][string]$Text)
    return ($Text -match '[^\x00-\x7F]')
}

function ConvertTo-UTAsciiScript {
    <#
        Rewrites every non-ASCII character of a PowerShell script so the result is pure ASCII
        and behaves the same. Throws when a character sits somewhere it cannot be rewritten.
    #>
    param([Parameter(Mandatory)][string]$Script, [string]$SourceName = 'script')

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($Script, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw "Erro de sintaxe em ${SourceName}: $($errors[0].Message) (linha $($errors[0].Extent.StartLineNumber))"
    }

    $replacements = New-Object System.Collections.Generic.List[object]
    foreach ($token in $tokens) {
        $text = $token.Text
        if (-not (Test-UTHasNonAscii $text)) { continue }

        $kind = [string]$token.Kind
        $new = $null
        switch ($kind) {
            'Comment' { $new = ConvertTo-UTFoldedAscii $text }
            'StringLiteral' {
                # 'text' -> "escaped text"
                $new = '"' + (ConvertTo-UTExpandableEscape -Text $token.Value) + '"'
            }
            'HereStringLiteral' {
                $nl = "`r`n"
                if ($text -notmatch "^@'\r\n") { $nl = "`n" }
                $new = '@"' + $nl + (ConvertTo-UTExpandableEscape -Text $token.Value -HereString) + $nl + '"@'
            }
            { $_ -in 'StringExpandable', 'HereStringExpandable' } {
                foreach ($nested in @($token.NestedTokens)) {
                    if ($null -ne $nested -and (Test-UTHasNonAscii $nested.Text)) {
                        throw "${SourceName} linha $($token.Extent.StartLineNumber): acento dentro de uma subexpressão de string. Mova o texto para uma variável."
                    }
                }
                $sb = New-Object System.Text.StringBuilder
                foreach ($ch in $text.ToCharArray()) {
                    if ([int]$ch -gt 127) { [void]$sb.AppendFormat('$([char]0x{0:X4})', [int]$ch) } else { [void]$sb.Append($ch) }
                }
                $new = $sb.ToString()
            }
            default {
                throw "${SourceName} linha $($token.Extent.StartLineNumber): caractere não ASCII fora de string ou comentário ($kind): $text"
            }
        }
        $replacements.Add([pscustomobject]@{ Start = $token.Extent.StartOffset; End = $token.Extent.EndOffset; Text = $new })
    }

    $sbOut = New-Object System.Text.StringBuilder($Script)
    foreach ($r in ($replacements | Sort-Object Start -Descending)) {
        [void]$sbOut.Remove($r.Start, $r.End - $r.Start)
        [void]$sbOut.Insert($r.Start, $r.Text)
    }
    return $sbOut.ToString()
}
