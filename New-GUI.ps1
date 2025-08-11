Add-Type -AssemblyName System.Windows.Forms, System.Drawing
function New-GUI_Extented {
    <#
        .SYNOPSIS
        génération d'un GUI Windows Forms à partir d'un XML

        .DESCRIPTION
        Fonction de génération récursive d'un GUI Windows Forms à partir d'un XML. Peut prendre en entrée un XML depuis une variable, un pipeline ou un fichier.
        Les différents Controls sont accessibles depuis l'objet retourné

        .PARAMETER Node
        Node XML issu de l'input ou de la récursivité

        .PARAMETER Parent
        Objet Windows.Form.Control parent du contrôle créé (pour la récursivité uniquement)

        .PARAMETER XMLPath
        Lien vers le fichier XML

        .EXAMPLE
        PS >$XML = ( [XML] "<?xml version='1.0'?>
            <Form Text='Recherche de fichiers' Size='400,500' AutoSize = 'True'>
                <Label Text='Hello World !' Size='40,50' Location='10,10'/>
                <Panel Size='100,500' Location='10,100' >
                    <Button ID='OK' Text='OK'  Size='40,50' Location='10,10'/>
                </Panel>
            </Form> " )

        PS >$GUI = New-GUI -Verbose -Node $XML
        PS >$GUI.Form.ShowDialog()
        .EXAMPLE
        PS >$GUI = New-GUI -XMLPath .\Xml\main.xml

        PS >$GUI.Label_Titre.Text = "Je change mon texte"
        PS >$GUI.Form.ShowDialog()
        .EXAMPLE
        PS >$GUI = ( [XML] "<?xml version='1.0'?>
            <Form Text='Recherche de fichiers' Size='400,500' AutoSize = 'True'>
                <Label Text='Hello World !' Size='40,50' Location='10,10'/>
                <Panel Size='100,500' Location='10,100' >
                    <Button ID='OK' Text='OK'  Size='40,50' Location='10,10'/>
                </Panel>
            </Form> " ) | New-GUI_Extented -Verbose 

        PS >$GUI.GetControls()

        Name   Path
        ----   ----
        Form   Form
        Label  Form\Label
        Panel  Form\Panel
        Button Form\Panel\Button
        .LINK
        Github : https://github.com/andruszko-pierre/PSTools/blob/main/New-GUI.ps1
#>
    [cmdletbinding()] # Verbose support

    param ( 
        [Parameter(ValueFromPipeline)] $Node, 
        [System.Windows.Forms.Control] $Parent, 
        [String] $XMLPath 
    )

    # le bloc process est requis pour ValueFromPipeline, pas d'accès à la valeur passée en pipe en dehors (ex dans un bloc begin)
    process { 
        try {
            # Si pas de valeur passée en pipe ou -Node, on présume un -XmlPath et le parse dans $Node = XML.Form  
            if ( -not $Node ) { 
                Write-Verbose "Getting content from XML File '$($XMLPath)'"
                $Node = ( [xml] $( Get-Content $XMLPath )).Form 
            }

            # Si $Node est la racine du XML, on lui passe l'objet Form
            if ($Node.Name -eq "#document") {
                Write-Verbose "Setting `$Node to XML.form" 
                $Node = $Node.Form 
            }

            # Si $Node est Form on init le conteneur GUI, on fait le test pour initialiser uniquement dans le premier niveau de récursivité 
            if ($Node.Name -eq "Form") { 
                Write-Verbose "Initialising GUI" 
                $GUI = @{}
                
                #<----- Pas dans la version minifié : Fonctions Debug
                $GUI | Add-Member -MemberType ScriptMethod -Name "GetControls" -Value({ $GUI | Get-Member | Where-Object {$_.MemberType -eq "NoteProperty"} | Select-Object Name, @{n='Path'; e={$GUI.($_.Name).Path}} | Sort-Object -Property Path })
                #----->
            }

            # On créé le Windows.Forms.Control correspondant au node (<Label /> ou <Label></Label>)
            $Control = New-Object System.Windows.Forms.$( $Node.Name )

            #<----- Pas dans la version minifié ( pour Verbose )
            $Name = "$(if ($Node.ID) {"$($Node.ID)_"})$($Node.Name)" # (ID_)Type
            $Path = "$(if ($Parent){"$($Parent.Path)\"})$Name"       # (Parent\Path\)Name
            Write-Verbose "Initialising $Path"
            $Control.Name = $Name
            $Control | Add-Member -MemberType NoteProperty -Name "Path" -Value $Path
            #----->
            
            # On lui assigne dynamiquement en tant que propriétés les différents Attributs du Node (<Label ID="Titre" Text="Hello World !" Size='40,50' Location='10,10'/>)
            foreach ( $Prop in $Node.Attributes ) { 
                try {

                    # Si l'attribut est une propriétée connue par l'objet Windows.Forms.Control utilisé
                    if ($Control.PSObject.Properties[$Prop.Name].IsSettable) { 

                        # On détecte le type attendu par la propriété
                        switch ( $Control.PSObject.Properties[$Prop.Name].TypeNameOfValue ) { 
                            'System.Drawing' { $Control.$($Prop.Name) = New-Object $_ ( $Prop.Value -split "," )} # Pour les types System.Drawing(.Size, .Point ....) on créé l'objet
                            default          { $Control.$($Prop.Name) = $Prop.Value -as ( $_ -as [type] )}        # Pour le reste on cast le type correspondant avec -as
                        }
                    Write-Verbose "   Setting prop : $Name.$($Prop.Name) as $($Control.PSObject.Properties[$Prop.Name].TypeNameOfValue)"    
                    }
                } 
                catch { Write-Error "Propriété ignorée : $( $Prop.Name ) ( valeur : $( $Prop.Value ) ) - $($_.Exception.Message)" }
            }

            # On ajoute le controle au conteneur GUI pour accès ultérieur (pour édition, actions ...) 
            # ex : <Form> ... </Form>                        => PS> $GUI.Form.ShowDialog() 
            # ex : <Label ID="Titre" Text="Hello World !" /> => PS> $GUI.Label_Titre.Text = "Je change mon texte"
            Write-Verbose "   Adding Control to GUI : $Name"
            $GUI | Add-Member -MemberType NoteProperty -Name "$(if ($Node.ID) {"$($Node.ID)_"})$($Node.Name)" -Value $Control        
            
            # On fait le traitement récursif des Enfants
            if ( $Node.HasChildNodes ) { $Node.ChildNodes | New-GUI_Extented -Parent $Control }

            # Si on à un -Parent (obj Windows.Forms.Control) on y ajoute le Control
            # Sinon on retourne le GUI, le Form est le seul conteneur sans Parent et grace à la récursivité il est le dernier à passer le test          
            if ( $Parent ) {
                Write-Verbose "   Adding to Control Parent : $Path"
                $Parent.Controls.Add( $Control ) 
            } 
            else { return $GUI }
        } 
        catch { Write-Error "Control ignoré : $( $Node.Name ) - $($_.Exception.Message)" }
    }
}

# Version Minifiée
function New-GUI( [Parameter(ValueFromPipeline)] $Node, $Parent, $XMLPath ) {
    # Help : https://github.com/andruszko-pierre/PSTools/blob/main/New-GUI.ps1
    process { try {  
        if ( -not $Node ) { $Node = ( [xml] $( Get-Content $XMLPath )).Form }
        if ($Node.Name -eq "#document") { $Node = [xml] $Node.Form }
        if ($Node.Name -eq "Form") { $GUI = @{} }       
        $Control = New-Object System.Windows.Forms.$( $Node.Name )       
        foreach ( $Prop in $Node.Attributes ) { try {
            if ($Control.PSObject.Properties[$Prop.Name].IsSettable) { 
                switch ( $Control.PSObject.Properties[$Prop.Name].TypeNameOfValue ) {
                    'System.Drawing' { $Control.$($Prop.Name) = New-Object $_ ( $Prop.Value -split "," )}
                    default          { $Control.$($Prop.Name) = $Prop.Value -as ( $_ -as [type] )}
        }}} catch { Write-Error "Propriété ignorée : $( $Prop.Name ) ( valeur : $( $Prop.Value ) )- $($_.Exception.Message)" }}       
        $GUI | Add-Member -MemberType NoteProperty -Name "$($Node.Name)$(if ($Node.ID) {"_$($Node.ID)"})" -Value $Control        
        if ( $Node.HasChildNodes ) { $Node.ChildNodes | New-GUI -Parent $Control }
        if ( $Parent ) { $Parent.Controls.Add( $Control ) } else { return $GUI }
    } catch { Write-Error "Control ignoré : $( $Node.Name ) - $($_.Exception.Message)" }}
}