# Startup manager ("Serviços e Apps" tab): programs that start with Windows from the Run keys,
# the Startup folders and logon scheduled tasks. Disabling uses the same StartupApproved flags as
# the Task Manager, so it is reversible and Windows shows the same state.

function Get-UTStartupSource {
    <#
    .SYNOPSIS
        Where startup entries come from. -Raiz* parameters exist for the tests.
    #>
    [CmdletBinding()]
    param(
        [string]$RaizUsuario = 'HKCU:\Software',
        [string]$RaizMaquina = 'HKLM:\SOFTWARE',
        [string]$PastaUsuario = [Environment]::GetFolderPath('Startup'),
        [string]$PastaComum = [Environment]::GetFolderPath('CommonStartup')
    )
    $approved = 'Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    @(
        [pscustomobject]@{ Tipo = 'run'; Origem = 'Registro (usuário)'; Caminho = "$RaizUsuario\Microsoft\Windows\CurrentVersion\Run"; Aprovacao = "$RaizUsuario\$approved\Run" }
        [pscustomobject]@{ Tipo = 'run'; Origem = 'Registro (todos os usuários)'; Caminho = "$RaizMaquina\Microsoft\Windows\CurrentVersion\Run"; Aprovacao = "$RaizMaquina\$approved\Run" }
        [pscustomobject]@{ Tipo = 'run'; Origem = 'Registro (todos os usuários, 32 bits)'; Caminho = "$RaizMaquina\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Aprovacao = "$RaizMaquina\$approved\Run32" }
        [pscustomobject]@{ Tipo = 'pasta'; Origem = 'Pasta Inicializar (usuário)'; Caminho = $PastaUsuario; Aprovacao = "$RaizUsuario\$approved\StartupFolder" }
        [pscustomobject]@{ Tipo = 'pasta'; Origem = 'Pasta Inicializar (todos os usuários)'; Caminho = $PastaComum; Aprovacao = "$RaizMaquina\$approved\StartupFolder" }
    )
}

function Test-UTStartupApproved {
    <#
    .SYNOPSIS
        StartupApproved value: first byte even = enabled, odd = disabled; missing = enabled.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Aprovacao, [Parameter(Mandatory)][string]$Nome)
    $v = Get-UTRegistryValue -Path $Aprovacao -Name $Nome
    if (-not $v.ValorExiste -or $v.Tipo -ne 'Binary' -or ([string]$v.Valor).Length -lt 2) { return $true }
    return (([Convert]::ToByte(([string]$v.Valor).Substring(0, 2), 16) % 2) -eq 0)
}

function Get-UTStartupItem {
    <#
    .SYNOPSIS
        Every startup entry with Nome, Comando, Origem, Ativo and what is needed to toggle it.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Fontes = @(Get-UTStartupSource),
        [switch]$SemTarefas
    )

    foreach ($src in $Fontes) {
        if ($src.Tipo -eq 'run') {
            $key = Open-UTRegistryKey -Path $src.Caminho
            if ($null -eq $key) { continue }
            try { $names = @($key.GetValueNames() | Where-Object { $_ }) } finally { $key.Dispose() }
            foreach ($n in $names) {
                [pscustomobject]@{
                    Nome = $n; Comando = [string](Get-UTRegistryValue -Path $src.Caminho -Name $n).Valor; Origem = $src.Origem
                    Tipo = 'run'; Ativo = (Test-UTStartupApproved -Aprovacao $src.Aprovacao -Nome $n); Aprovacao = $src.Aprovacao; Tarefa = $null
                }
            }
        } elseif ($src.Tipo -eq 'pasta') {
            if (-not $src.Caminho -or -not (Test-Path -LiteralPath $src.Caminho)) { continue }
            foreach ($f in @(Get-ChildItem -LiteralPath $src.Caminho -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
                [pscustomobject]@{
                    Nome = $f.Name; Comando = $f.FullName; Origem = $src.Origem
                    Tipo = 'pasta'; Ativo = (Test-UTStartupApproved -Aprovacao $src.Aprovacao -Nome $f.Name); Aprovacao = $src.Aprovacao; Tarefa = $null
                }
            }
        }
    }

    if (-not $SemTarefas) {
        foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })) {
            $logon = @($t.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' }).Count -gt 0
            if (-not $logon) { continue }
            [pscustomobject]@{
                Nome = $t.TaskName; Comando = (@($t.Actions | ForEach-Object { ("$($_.Execute) $($_.Arguments)").Trim() }) -join '; '); Origem = 'Tarefa agendada (ao entrar)'
                Tipo = 'tarefa'; Ativo = ([string]$t.State -ne 'Disabled'); Aprovacao = $null; Tarefa = ($t.TaskPath + $t.TaskName)
            }
        }
    }
}

function Set-UTStartupItemState {
    <#
    .SYNOPSIS
        Enables or disables one startup entry (from Get-UTStartupItem).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][psobject]$Item,
        [Parameter(Mandatory)][bool]$Ativo
    )
    $verb = $(if ($Ativo) { 'Ativar na inicialização' } else { 'Desativar na inicialização' })
    if (-not $PSCmdlet.ShouldProcess($Item.Nome, $verb)) { return }

    if ($Item.Tipo -eq 'tarefa') {
        $path = $Item.Tarefa.Substring(0, $Item.Tarefa.LastIndexOf('\') + 1)
        $name = $Item.Tarefa.Substring($Item.Tarefa.LastIndexOf('\') + 1)
        if ($Ativo) { Enable-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop | Out-Null }
        else { Disable-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop | Out-Null }
    } else {
        if ($Ativo) {
            $data = '020000000000000000000000'
        } else {
            # 03 + 3 zero bytes + FILETIME of when it was disabled, as the Task Manager writes it.
            $ft = [BitConverter]::GetBytes((Get-Date).ToFileTime())
            $data = '03000000' + (($ft | ForEach-Object { $_.ToString('X2') }) -join '')
        }
        Set-UTRegistryValue -Path $Item.Aprovacao -Name $Item.Nome -Type Binary -Value $data
    }
    Write-UTLog -Level Sucesso -Message "$($verb): $($Item.Nome)"
}
