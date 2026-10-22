BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-UTUiAssembly
    function Initialize-TestWindow {
        Reset-UTTestEnvironment
        $ui = Initialize-UTUiState
        $w = Get-UTUiWindow -Name 'MainWindow'
        $ui.Window = $w.Window
        $ui.C = $w.Controles
        Initialize-UTUiNavigation
        return $ui
    }
}
AfterAll { Clear-UTTestEnvironment }

Describe 'Design system' {
    It 'todos os arquivos de tema carregam e têm as mesmas chaves nos dois temas' {
        $dark = [Windows.Markup.XamlReader]::Parse((Get-UTXamlText -Name 'Theme\Escuro'))
        $light = [Windows.Markup.XamlReader]::Parse((Get-UTXamlText -Name 'Theme\Claro'))
        [void][Windows.Markup.XamlReader]::Parse((Get-UTXamlText -Name 'Theme\Controles'))
        $k1 = @($dark.Keys | ForEach-Object { [string]$_ } | Sort-Object)
        $k2 = @($light.Keys | ForEach-Object { [string]$_ } | Sort-Object)
        $k1 | Should -Be $k2
        foreach ($k in 'BgBrush', 'CardBrush', 'TextBrush', 'MutedBrush', 'AccentBrush', 'SeparatorBrush', 'IconBlue') { $k1 | Should -Contain $k }
    }

    It 'a janela e os estilos usam só DynamicResource para cores (troca de tema ao vivo)' {
        foreach ($name in 'MainWindow', 'Theme\Controles') {
            $text = Get-UTXamlText -Name $name
            $text | Should -Not -Match 'StaticResource\s+\w*Brush' -Because $name
        }
    }

    It 'tema "sistema" segue o modo de app do Windows' {
        Mock Get-ItemProperty { [pscustomobject]@{ AppsUseLightTheme = 1 } } -ParameterFilter { $Name -eq 'AppsUseLightTheme' }
        Resolve-UTUiThemeName -Tema sistema | Should -Be 'claro'
        Mock Get-ItemProperty { [pscustomobject]@{ AppsUseLightTheme = 0 } } -ParameterFilter { $Name -eq 'AppsUseLightTheme' }
        Resolve-UTUiThemeName -Tema sistema | Should -Be 'escuro'
        Resolve-UTUiThemeName -Tema claro | Should -Be 'claro'
    }

    It 'cor de destaque gera as variações de cada tema' {
        $d = Get-UTUiAccentSet -Hex '#0A84FF' -Tema escuro
        $d.AccentBrush.Color.ToString() | Should -Be '#FF0A84FF'
        $d.AccentSoftBrush.Color.A | Should -Be 0x33
        $d.AccentLightBrush.Color.R | Should -BeGreaterThan 0x0A
        $l = Get-UTUiAccentSet -Hex '#0A84FF' -Tema claro
        $l.AccentLightBrush.Color.B | Should -BeLessThan 0xFF
    }

    It 'Mica só no Windows 11; Windows 10 fica com fundo sólido' {
        Get-UTUiBackdropKind -Build 26100 | Should -Be 'mica'
        Get-UTUiBackdropKind -Build 22000 | Should -Be 'mica-antigo'
        Get-UTUiBackdropKind -Build 19045 | Should -Be 'nenhum'
    }

    It 'preferências da janela persistem em %AppData% (pasta do usuário) e voltam com padrões' {
        Reset-UTTestEnvironment
        (Get-UTUiPreference).Tema | Should -Be 'sistema'
        Save-UTUiPreference -Valores @{ Tema = 'claro'; Pagina = 'GPU'; Largura = 1500 } -Confirm:$false
        $p = Get-UTUiPreference
        $p.Tema | Should -Be 'claro'
        $p.Pagina | Should -Be 'GPU'
        $p.Largura | Should -Be 1500
        $p.Destaque | Should -Be '#7C3AED'
        Test-Path (Join-Path (Get-UTPath -Name Usuario) 'ui.json') | Should -BeTrue
    }

    It 'a barra lateral tem as seções e só as abas são selecionáveis' {
        $ui = Initialize-TestWindow
        $items = @($ui.C['NavList'].Items)
        $headers = @($items | Where-Object { -not $_.IsEnabled })
        @($headers | ForEach-Object Content) | Should -Be @('Otimização', 'Sistema', 'Geral')
        @($items | Where-Object { $_.IsEnabled }).Count | Should -Be @(Get-UTUiTabDefinition).Count
    }

    It 'troca de tema refaz as páginas e salva a escolha' {
        $ui = Initialize-TestWindow
        Mock Invoke-UTUiJob { [pscustomobject]@{ Nome = $Nome } }
        Show-UTUiPage -Id 'Sobre'
        Switch-UTUiTheme -Tema escuro
        (Get-UTUiPreference).Tema | Should -Be 'escuro'
        $ui.Window.Resources['TemaAtual'] | Should -Be 'escuro'
        $ui.PaginaAtual | Should -Be 'Sobre'
        $ui.Pages.ContainsKey('Sobre') | Should -BeTrue
    }

    It 'a Galeria monta com todos os componentes' {
        $ui = Initialize-TestWindow
        Mock Invoke-UTUiJob { [pscustomobject]@{ Nome = $Nome } }
        { Show-UTUiPage -Id 'Galeria' } | Should -Not -Throw
        $ui.Pages['Galeria'] | Should -BeOfType System.Windows.UIElement
        $ui.C['TitleText'].Text | Should -Be 'Galeria de componentes'
    }

    It 'sem a janela aberta, o sheet vira uma janela de diálogo' {
        $null = Initialize-TestWindow
        Mock Show-UTUiDialogWindow { 'OK' }
        Show-UTUiSheet -Titulo 'x' -Mensagem 'y' | Should -Be 'OK'
        Should -Invoke Show-UTUiDialogWindow -Times 1
    }

    It 'componentes: switch chama a ação ao mudar; grupo separa as linhas' {
        $null = Initialize-TestWindow
        $script:changed = $null
        $sw = New-UTUiSwitch -Marcado $false -Dados 'x' -AoMudar { param($s, $d) $script:changed = "$d=$($s.IsChecked)" }
        $sw.IsChecked = $true
        $script:changed | Should -Be 'x=True'
        $g = New-UTUiGroup -Titulo 'Grupo' -Linhas @((New-UTUiRow -Titulo 'A'), (New-UTUiRow -Titulo 'B' -Subtitulo 'b'), (New-UTUiRow -Titulo 'C'))
        $inner = $g.Children[1].Child
        $inner.Children.Count | Should -Be 5   # 3 rows + 2 separators
    }

    It 'anel da nota: arco proporcional, círculo cheio em 100, nome para leitor de tela' {
        $null = Initialize-TestWindow
        $r = New-UTUiScoreRing -Nota 75 -Cor 'GreenBrush'
        $r.Children.Count | Should -Be 3
        $r.Children[1] | Should -BeOfType System.Windows.Shapes.Path
        $r.Children[1].Data.Bounds.Width | Should -BeGreaterThan 100
        [System.Windows.Automation.AutomationProperties]::GetName($r) | Should -Match '75 de 100'
        (New-UTUiScoreRing -Nota 100).Children[1] | Should -BeOfType System.Windows.Shapes.Ellipse
        (New-UTUiScoreRing -Nota 0).Children[1] | Should -BeOfType System.Windows.Shapes.Path
    }
}