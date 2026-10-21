function Get-UTGeneratedTweak {
    <#
    .SYNOPSIS
        Tweaks built from data files instead of being written one by one in tweaks-*.json:
        one per service in services.json, one for the "Modo Lite" Manual list, and one per app
        in apps-debloat.json. Returns nothing while those files do not exist.
    #>
    [CmdletBinding()]
    param()
    if (Test-UTConfigFile -Name 'services') { ConvertTo-UTServiceTweak -Config (Get-UTConfig -Name 'services') }
    if (Test-UTConfigFile -Name 'apps-debloat') { ConvertTo-UTAppTweak -Config (Get-UTConfig -Name 'apps-debloat') }
    if (Test-UTConfigFile -Name 'dns') { ConvertTo-UTDnsTweak -Config (Get-UTConfig -Name 'dns') }
}

function ConvertTo-UTDnsTweak {
    <#
    .SYNOPSIS
        One exclusive tweak per DNS provider (UT_Net_DNS_<id>). Undoing goes back to what each
        adapter had (usually the internet provider's DNS via DHCP).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    foreach ($p in @($Config.provedores)) {
        $id = [string]$p.id
        [ordered]@{
            id              = 'UT_Net_DNS_' + (ConvertTo-UTTweakIdPart $id)
            nome            = "DNS: $($p.nome)"
            descricao       = "Usa o DNS $($p.nome) (IPv4 $(@($p.ipv4) -join ' / ') e IPv6) em todas as conexões ativas. $($p.descricao) O DNS só influencia o tempo para achar endereços (abrir sites, entrar no lobby); não muda o ping dentro da partida. Use o teste de DNS da aba Rede para ver qual é o mais rápido na sua internet."
            ganhoEsperado   = 'Nenhum no ping da partida; carregamentos de sites e lobby podem ficar mais rápidos'
            categoria       = 'Rede'
            risco           = 'baixo'
            requerReinicio  = $false
            controverso     = $false
            grupoExclusivo  = 'dns'
            compatibilidade = [ordered]@{ windows = @('10', '11') }
            scriptAplicar   = @("Set-UTDnsProvider -Provedor '$id' -TweakId `$TweakId")
            scriptDesfazer  = @('Restore-UTDnsProvider -TweakId $TweakId')
            scriptDetectar  = @("Test-UTDnsProvider -Provedor '$id'")
            scriptSimular   = @("Get-UTDnsTargetInterface | ForEach-Object { `"DNS de `$(`$_.Name): $($p.nome)`" }")
            deteccao        = 'script'
        }
    }
}

function ConvertTo-UTTweakIdPart {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Text)
    return ($Text -replace '[^A-Za-z0-9]', '_')
}

function ConvertTo-UTServiceTweak {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)

    foreach ($s in @($Config.servicos)) {
        $compat = [ordered]@{ windows = @('10', '11') }
        $note = ''
        if ($s.grupo -eq 'xbox') {
            $compat['launchersBloqueados'] = @('xbox')
            $note = 'Bloqueado automaticamente quando o Call of Duty é do Xbox App/Game Pass. Nunca entra nos presets: só manual.'
        }
        $startNames = @{ Automatic = 'Automático'; AutomaticDelayedStart = 'Automático (atraso)'; Manual = 'Manual'; Disabled = 'Desativado' }
        [ordered]@{
            id              = 'UT_Svc_' + (ConvertTo-UTTweakIdPart $s.nome)
            nome            = "Serviço $($s.exibicao): $($startNames[[string]$s.recomendado])"
            descricao       = [string]$s.descricao
            ganhoEsperado   = $(if (Get-UTField $s 'ganhoEsperado') { [string](Get-UTField $s 'ganhoEsperado') } else { 'Pequeno (menos atividade em segundo plano)' })
            categoria       = 'ServicosApps'
            risco           = [string]$s.risco
            requerReinicio  = $false
            controverso     = $false
            observacao      = $note
            compatibilidade = $compat
            servicos        = @([ordered]@{ nome = [string]$s.nome; inicio = [string]$s.recomendado; inicioOriginal = [string]$s.padrao; parar = ($s.recomendado -eq 'Disabled') })
            deteccao        = 'servicos'
            grupoServico    = [string]$s.grupo
            opcional        = [bool](Get-UTField $s 'opcional' $false)
        }
    }

    $lite = $Config.modoLiteManual
    if ($lite -and @($lite.servicos).Count -gt 0) {
        [ordered]@{
            id              = 'UT_Svc_ModoLiteManual'
            nome            = 'Serviços que iniciam com o Windows em Manual (Modo Lite)'
            descricao       = [string]$lite.descricao + ' Serviços: ' + ((@($lite.servicos) | ForEach-Object { $_.nome }) -join ', ') + '.'
            ganhoEsperado   = 'Pequeno (menos processos ao ligar o PC)'
            categoria       = 'ServicosApps'
            risco           = 'médio'
            requerReinicio  = $false
            controverso     = $false
            compatibilidade = [ordered]@{ windows = @('10', '11') }
            servicos        = @(@($lite.servicos) | ForEach-Object { [ordered]@{ nome = [string]$_.nome; inicio = 'Manual'; inicioOriginal = [string]$_.padrao; parar = $false } })
            deteccao        = 'servicos'
            grupoServico    = 'lite'
            opcional        = $true
        }
    }
}

function ConvertTo-UTAppTweak {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)

    foreach ($a in @($Config.apps)) {
        $pkg = ([string]$a.pacote).Replace("'", "''")
        $name = ([string]$a.nome).Replace("'", "''")
        $undoText = $(if (Get-UTField $a 'storeId') { 'Desfazer reinstala pela Microsoft Store.' } else { 'Para voltar, reinstale pela Microsoft Store (não há reinstalação automática para este app).' })
        $undo = $(if (Get-UTField $a 'storeId') { "Install-UTStoreApp -StoreId '$($a.storeId)' -Nome '$name'" } else { "Write-UTLog -Level Aviso -TweakId `$TweakId -Message 'Reinstale $name pela Microsoft Store, se quiser de volta.'" })
        [ordered]@{
            id              = 'UT_App_' + (ConvertTo-UTTweakIdPart $a.pacote)
            nome            = "Remover o app $($a.nome)"
            descricao       = "$($a.descricao) Remove o app de todos os usuários e da imagem do Windows (contas novas não recebem). $undoText"
            ganhoEsperado   = 'Nenhum em FPS; menos apps e tarefas em segundo plano'
            categoria       = 'ServicosApps'
            risco           = 'baixo'
            requerReinicio  = $false
            controverso     = $false
            compatibilidade = [ordered]@{ windows = @('10', '11') }
            scriptAplicar   = @("Remove-UTAppxPackage -Pacote '$pkg' -TweakId `$TweakId")
            scriptDesfazer  = @($undo)
            scriptDetectar  = @("Test-UTAppxRemoved -Pacote '$pkg'")
            scriptSimular   = @("'Remove o app $name ($pkg) de todos os usuários'")
            deteccao        = 'script'
            debloatPadrao   = [bool](Get-UTField $a 'padrao' $false)
            pacote          = [string]$a.pacote
        }
    }
}
