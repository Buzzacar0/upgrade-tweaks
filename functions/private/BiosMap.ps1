# BIOS settings map: reads the text that IFRExtractor-RS writes from the setup modules of a
# BIOS image (UEFI Internal Form Representation) and keeps, for every question, where its value
# lives in the NVRAM (variable, offset, size), its options and the conditions that hide it.

function Join-UTIfrLine {
    <#
    .SYNOPSIS
        Logical lines of an IFR text: help texts may span several physical lines, so a line with
        an open quote is joined with the next ones. Returns @{ Nivel (tabs); Texto }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Linhas)
    $current = $null
    $level = 0
    foreach ($raw in $Linhas) {
        if ($null -eq $current) {
            $level = 0
            while ($level -lt $raw.Length -and $raw[$level] -eq "`t") { $level++ }
            $current = $raw.Substring($level)
        } else {
            $current += "`n" + $raw
        }
        if (($current.Split('"').Count - 1) % 2 -eq 0) {
            if ($current.Trim()) { [pscustomobject]@{ Nivel = $level; Texto = $current.TrimEnd() } }
            $current = $null
        }
    }
    if ($null -ne $current -and $current.Trim()) { [pscustomobject]@{ Nivel = $level; Texto = $current.TrimEnd() } }
}

function ConvertFrom-UTIfrNumber {
    param([AllowEmptyString()][string]$Texto)
    $t = $Texto.Trim()
    if ($t -match '^0x([0-9A-Fa-f]+)$') { return [Convert]::ToUInt64($Matches[1], 16) }
    if ($t -match '^\d+$') { return [uint64]$t }
    return $null
}

function Get-UTIfrField {
    # Value of "Campo: valor" or "Campo: "texto"" in one IFR line.
    param([Parameter(Mandatory)][string]$Linha, [Parameter(Mandatory)][string]$Campo)
    $m = [regex]::Match($Linha, '(?s)(?:^|[\s,])' + [regex]::Escape($Campo) + ':\s*("(?<q>[^"]*)"|(?<v>[^,\s]+))')
    if (-not $m.Success) { return $null }
    if ($m.Groups['q'].Success) { return $m.Groups['q'].Value }
    return $m.Groups['v'].Value
}

function ConvertFrom-UTIfrText {
    <#
    .SYNOPSIS
        Parses one IFRExtractor text into variable stores and questions (OneOf, CheckBox, Numeric).
    .DESCRIPTION
        Scopes follow the indentation: a line opens a scope when the next one is indented deeper,
        and "End" closes it. SuppressIf / GrayOutIf / DisableIf collect the expression opcodes that
        follow them (postfix) until the first statement; each question keeps a copy of every
        condition that encloses it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Linhas,
        [string]$Modulo = ''
    )
    $exprOps = @('EqIdVal', 'EqIdValList', 'EqIdId', 'QuestionRef1', 'Uint8', 'Uint16', 'Uint32', 'Uint64', 'True', 'False', 'Not', 'And', 'Or',
        'Equal', 'NotEqual', 'GreaterThan', 'GreaterEqual', 'LessThan', 'LessEqual', 'BitwiseAnd', 'BitwiseOr', 'One', 'Zero', 'Ones')
    $questionOps = @('OneOf', 'CheckBox', 'Numeric')
    $lines = @(Join-UTIfrLine -Linhas $Linhas)
    $stores = New-Object System.Collections.Generic.List[object]
    $questions = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.List[object]
    $formset = -1
    $formsetTitle = ''

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $text = $lines[$i].Texto
        $opensScope = ($i + 1 -lt $lines.Count -and $lines[$i + 1].Nivel -gt $lines[$i].Nivel)
        $op = ([regex]::Match($text, '^[A-Za-z][A-Za-z0-9]*')).Value

        if ($op -eq 'End') {
            if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) }
            continue
        }

        $collecting = $null
        if ($stack.Count -gt 0) {
            $top = $stack[$stack.Count - 1]
            if ($top.Tipo -eq 'Condicao' -and $top.Coletando) { $collecting = $top }
            elseif ($top.Tipo -eq 'Expressao') { $collecting = $top.Condicao }
        }
        if ($collecting -and $exprOps -contains $op) {
            $collecting.Expr.Add($text)
            if ($opensScope) { $stack.Add(@{ Tipo = 'Expressao'; Condicao = $collecting }) }
            continue
        }
        # The first statement ends the expressions of the open conditions.
        foreach ($s in $stack) { if ($s.Tipo -eq 'Condicao') { $s.Coletando = $false } }

        switch ($op) {
            'FormSet' {
                $formset++
                $formsetTitle = [string](Get-UTIfrField -Linha $text -Campo 'Title')
                if ($opensScope) { $stack.Add(@{ Tipo = 'FormSet' }) }
                continue
            }
            { $_ -in 'VarStore', 'VarStoreEfi' } {
                $stores.Add([pscustomobject]@{
                        Formset   = $formset
                        Id        = [int](ConvertFrom-UTIfrNumber (Get-UTIfrField -Linha $text -Campo 'VarStoreId'))
                        Nome      = [string](Get-UTIfrField -Linha $text -Campo 'Name')
                        Guid      = ([string](Get-UTIfrField -Linha $text -Campo 'Guid')).ToUpperInvariant()
                        Tamanho   = [int](ConvertFrom-UTIfrNumber (Get-UTIfrField -Linha $text -Campo 'Size'))
                        Atributos = $(if ($op -eq 'VarStoreEfi') { [int](ConvertFrom-UTIfrNumber (Get-UTIfrField -Linha $text -Campo 'Attributes')) } else { $null })
                    })
                if ($opensScope) { $stack.Add(@{ Tipo = 'Outro' }) }
                continue
            }
            'Form' {
                if ($opensScope) { $stack.Add(@{ Tipo = 'Form'; Titulo = [string](Get-UTIfrField -Linha $text -Campo 'Title') }) }
                continue
            }
            { $_ -in 'SuppressIf', 'GrayOutIf', 'DisableIf' } {
                if ($opensScope) { $stack.Add(@{ Tipo = 'Condicao'; Condicao = $op; Expr = (New-Object System.Collections.Generic.List[string]); Coletando = $true }) }
                continue
            }
            { $questionOps -contains $_ } {
                $size = $(if ($op -eq 'CheckBox') { 8 } else { [int](ConvertFrom-UTIfrNumber (Get-UTIfrField -Linha $text -Campo 'Size')) })
                $conds = @(foreach ($s in $stack) { if ($s.Tipo -eq 'Condicao') { [pscustomobject]@{ Tipo = $s.Condicao; Expr = @($s.Expr) } } })
                $form = (@($stack | Where-Object { $_.Tipo -eq 'Form' }) | Select-Object -Last 1)
                $q = [pscustomobject]@{
                    Modulo     = $Modulo
                    Formset    = $formset
                    Menu       = $formsetTitle
                    Formulario = $(if ($form) { [string]$form.Titulo } else { '' })
                    Nome       = ([string](Get-UTIfrField -Linha $text -Campo 'Prompt')).Trim()
                    Ajuda      = ([string](Get-UTIfrField -Linha $text -Campo 'Help')).Trim()
                    Tipo       = $op
                    Qid        = [int](ConvertFrom-UTIfrNumber (Get-UTIfrField -Linha $text -Campo 'QuestionId'))
                    VarStoreId = [int](ConvertFrom-UTIfrNumber (Get-UTIfrField -Linha $text -Campo 'VarStoreId'))
                    Offset     = [int](ConvertFrom-UTIfrNumber (Get-UTIfrField -Linha $text -Campo 'VarOffset'))
                    Bits       = $size
                    Min        = (ConvertFrom-UTIfrNumber ([string](Get-UTIfrField -Linha $text -Campo 'Min')))
                    Max        = (ConvertFrom-UTIfrNumber ([string](Get-UTIfrField -Linha $text -Campo 'Max')))
                    Passo      = (ConvertFrom-UTIfrNumber ([string](Get-UTIfrField -Linha $text -Campo 'Step')))
                    Padrao     = $null
                    Opcoes     = (New-Object System.Collections.Generic.List[object])
                    Condicoes  = $conds
                }
                if ($op -eq 'CheckBox') {
                    $q.Opcoes.Add([pscustomobject]@{ Texto = 'Disabled'; Valor = [uint64]0 })
                    $q.Opcoes.Add([pscustomobject]@{ Texto = 'Enabled'; Valor = [uint64]1 })
                    $q.Padrao = $(if ([string](Get-UTIfrField -Linha $text -Campo 'Default') -eq 'Enabled') { [uint64]1 } else { [uint64]0 })
                }
                $questions.Add($q)
                if ($opensScope) { $stack.Add(@{ Tipo = 'Pergunta'; Pergunta = $q }) }
                continue
            }
            'OneOfOption' {
                $owner = (@($stack | Where-Object { $_.Tipo -eq 'Pergunta' }) | Select-Object -Last 1)
                if ($owner) {
                    $value = ConvertFrom-UTIfrNumber ([string](Get-UTIfrField -Linha $text -Campo 'Value'))
                    $owner.Pergunta.Opcoes.Add([pscustomobject]@{ Texto = ([string](Get-UTIfrField -Linha $text -Campo 'Option')).Trim(); Valor = $value })
                    if ($text -match ',\s*Default\b' -and $null -eq $owner.Pergunta.Padrao) { $owner.Pergunta.Padrao = $value }
                }
                if ($opensScope) { $stack.Add(@{ Tipo = 'Outro' }) }
                continue
            }
            'Default' {
                $owner = (@($stack | Where-Object { $_.Tipo -eq 'Pergunta' }) | Select-Object -Last 1)
                if ($owner -and (ConvertFrom-UTIfrNumber ([string](Get-UTIfrField -Linha $text -Campo 'DefaultId'))) -eq 0) {
                    $v = ConvertFrom-UTIfrNumber ([string](Get-UTIfrField -Linha $text -Campo 'Value'))
                    if ($null -ne $v) { $owner.Pergunta.Padrao = $v }
                }
                if ($opensScope) { $stack.Add(@{ Tipo = 'Outro' }) }
                continue
            }
            default {
                if ($opensScope) { $stack.Add(@{ Tipo = 'Outro' }) }
            }
        }
    }
    # Plain arrays: @() over a generic List trips a call-site cache bug of Windows PowerShell 5.1
    # ("Argument types do not match") when the same code also sees arrays.
    foreach ($q in $questions) { $q.Opcoes = $q.Opcoes.ToArray() }
    return [pscustomobject]@{ VarStores = $stores.ToArray(); Perguntas = $questions.ToArray() }
}

function Get-UTBiosBytesValue {
    # Little-endian unsigned value of -Bits bits at -Offset; $null when out of range.
    param([AllowNull()][byte[]]$Dados, [int]$Offset, [int]$Bits)
    $n = [int][math]::Max(1, $Bits / 8)
    if ($null -eq $Dados -or $Offset -lt 0 -or $Offset + $n -gt $Dados.Length) { return $null }
    [uint64]$v = 0
    for ($k = $n - 1; $k -ge 0; $k--) { $v = ($v -shl 8) -bor [uint64]$Dados[$Offset + $k] }
    return $v
}

function Set-UTBiosBytesValue {
    # Copy of -Dados with -Valor written little-endian at -Offset.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Works on a byte array in memory.')]
    param([Parameter(Mandatory)][byte[]]$Dados, [int]$Offset, [int]$Bits, [uint64]$Valor)
    $n = [int][math]::Max(1, $Bits / 8)
    if ($Offset -lt 0 -or $Offset + $n -gt $Dados.Length) { throw 'Posição fora da variável da NVRAM.' }
    $copy = [byte[]]$Dados.Clone()
    $v = $Valor
    for ($k = 0; $k -lt $n; $k++) { $copy[$Offset + $k] = [byte]($v -band 0xFF); $v = $v -shr 8 }
    return , $copy
}

function Get-UTIfrQuestionValue {
    # Current value of the question referenced by -Campo in an expression line, or $null.
    param([hashtable]$Valores, [string]$Linha, [string]$Campo)
    $qid = [int](ConvertFrom-UTIfrNumber (Get-UTIfrField -Linha $Linha -Campo $Campo))
    if ($Valores.ContainsKey($qid)) { return $Valores[$qid] }
    return $null
}

function Test-UTIfrExpression {
    <#
    .SYNOPSIS
        Evaluates a postfix IFR expression. -Valores maps question id -> current value.
        Returns $true / $false, or $null when something cannot be evaluated.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Expr,
        [Parameter(Mandatory)][hashtable]$Valores
    )
    $st = New-Object System.Collections.Generic.Stack[object]
    foreach ($line in $Expr) {
        $op = ([regex]::Match($line, '^[A-Za-z][A-Za-z0-9]*')).Value
        switch ($op) {
            'EqIdVal' {
                $a = Get-UTIfrQuestionValue -Valores $Valores -Linha $line -Campo 'QuestionId'
                if ($null -eq $a) { return $null }
                $st.Push([bool]($a -eq (ConvertFrom-UTIfrNumber (Get-UTIfrField -Linha $line -Campo 'Value'))))
            }
            'EqIdValList' {
                $a = Get-UTIfrQuestionValue -Valores $Valores -Linha $line -Campo 'QuestionId'
                if ($null -eq $a) { return $null }
                $list = @([regex]::Match($line, 'Values:\s*\[([^\]]*)\]').Groups[1].Value -split ',' | Where-Object { $_.Trim() } | ForEach-Object { ConvertFrom-UTIfrNumber $_ })
                $st.Push([bool]($list -contains $a))
            }
            'EqIdId' {
                $a = Get-UTIfrQuestionValue -Valores $Valores -Linha $line -Campo 'QuestionId'
                $b = Get-UTIfrQuestionValue -Valores $Valores -Linha $line -Campo 'OtherQuestionId'
                if ($null -eq $a -or $null -eq $b) { return $null }
                $st.Push([bool]($a -eq $b))
            }
            'QuestionRef1' {
                $a = Get-UTIfrQuestionValue -Valores $Valores -Linha $line -Campo 'QuestionId'
                if ($null -eq $a) { return $null }
                $st.Push([uint64]$a)
            }
            { $_ -in 'Uint8', 'Uint16', 'Uint32', 'Uint64' } { $st.Push((ConvertFrom-UTIfrNumber (Get-UTIfrField -Linha $line -Campo 'Value'))) }
            'True' { $st.Push($true) }
            'False' { $st.Push($false) }
            'One' { $st.Push([uint64]1) }
            'Zero' { $st.Push([uint64]0) }
            'Not' { if ($st.Count -lt 1) { return $null }; $st.Push(-not [bool]$st.Pop()) }
            { $_ -in 'And', 'Or', 'Equal', 'NotEqual', 'GreaterThan', 'GreaterEqual', 'LessThan', 'LessEqual', 'BitwiseAnd', 'BitwiseOr' } {
                if ($st.Count -lt 2) { return $null }
                $b = $st.Pop(); $a = $st.Pop()
                $num = { param($x) if ($x -is [bool]) { [uint64][int]$x } else { [uint64]$x } }
                $r = switch ($op) {
                    'And' { [bool]$a -and [bool]$b }
                    'Or' { [bool]$a -or [bool]$b }
                    'Equal' { (& $num $a) -eq (& $num $b) }
                    'NotEqual' { (& $num $a) -ne (& $num $b) }
                    'GreaterThan' { (& $num $a) -gt (& $num $b) }
                    'GreaterEqual' { (& $num $a) -ge (& $num $b) }
                    'LessThan' { (& $num $a) -lt (& $num $b) }
                    'LessEqual' { (& $num $a) -le (& $num $b) }
                    'BitwiseAnd' { (& $num $a) -band (& $num $b) }
                    'BitwiseOr' { (& $num $a) -bor (& $num $b) }
                }
                $st.Push($r)
            }
            default { return $null }
        }
    }
    if ($st.Count -ne 1) { return $null }
    $top = $st.Pop()
    if ($top -is [bool]) { return $top }
    return ([uint64]$top -ne 0)
}
