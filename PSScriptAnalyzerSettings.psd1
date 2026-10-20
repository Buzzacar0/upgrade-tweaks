@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Ferramenta interativa: saida colorida no console e intencional.
        'PSAvoidUsingWriteHost'
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.4')
        }
    }
}
