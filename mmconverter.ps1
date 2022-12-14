Param(
    [Parameter(Mandatory)][string]$exportZip,
    [Parameter(Mandatory)][string]$exportUserCsv,
    [Parameter(Mandatory)][string]$teamName,
    [string]$outputZip = "import.zip",
    [switch]$jsonlOnly
)

$exportDataPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
$outputDataPath = $jsonlOnly ? "." : (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName()))
$attachmentDir = "bulk-export-attachments"
$attachmentPath = Join-Path $outputDataPath (Join-Path "data" $attachmentDir)
$outputFilename = "import.jsonl"
$outputFilePath = Join-Path $outputDataPath $outputFilename

if (-not $jsonlOnly) {
    New-Item -ItemType Directory -Path $outputDataPath,$attachmentPath
}

Expand-Archive -Path $exportZip -DestinationPath $exportDataPath

$slackUsers = Get-Content (Join-Path $exportDataPath "users.json") | ConvertFrom-Json
$slackChannels = Get-Content (Join-Path $exportDataPath "channels.json") | ConvertFrom-Json
$userTable = @{}
Get-Content $exportUserCsv | ConvertFrom-Csv | ForEach-Object {
    $userTable[$_.userid] = $_
}

$botOwner = @{}

$mmTeam = [PSCustomObject]@{name=$teamName; display_name=$teamName; type="O"; description=""; allow_open_invite=$false}

$mmChannels = $slackChannels | ForEach-Object {
    $_.id = if ($_.is_general) {
        "town-square"
    } elseif ($_.name -match "^[a-z0-9-]+$") {
        $_.name
    } else {
        $_.id.ToLower()
    }
    [PSCustomObject]@{
        team = $teamName;
        name = $_.id;
        display_name = $_.name;
        type = "O"; #slack側に情報がないため固定値
        header = $_.topic.value;
        purpose = $_.purpose.value;
    }
}

[PSCustomObject]@{type="version"; version=1} | ConvertTo-Json -Compress -EscapeHandling EscapeHtml | Set-Content -Path $outputFilePath
[PSCustomObject]@{type="team"; team=$mmTeam} | ConvertTo-Json -Compress -EscapeHandling EscapeHtml | Add-Content -Path $outputFilePath
$mmChannels | ForEach-Object {[PSCustomObject]@{type="channel"; channel=$_} | ConvertTo-Json -Compress -EscapeHandling EscapeHtml} | Add-Content -Path $outputFilePath

$mmUsers = $slackUsers | ForEach-Object {
    $id = $_.id
    [PSCustomObject]@{
        username = $_.name;
        email = $userTable[$_.id].email;
        auth_service = $null; #slack側に情報がないため固定値
        nickname = ""; #slack側に情報がないため固定値
        first_name = $_.is_bot ? "" : ($_.real_name -split " ")[0];
        last_name = $_.is_bot ? "" : ($_.real_name -split " ")[-1];
        position = ""; #slack側に情報がないため固定値
        roles = "system_user"; #とりあえず固定値
        locale = $null; #slack側に情報がないため固定値 ただしタイムゾーン情報はある
        teams = @(
            [PSCustomObject]@{
                name = $teamName;
                roles = "team_user";
                channels = @($slackChannels | Where-Object {$_.members -contains $id} | ForEach-Object {
                    [PSCustomObject]@{
                        name = $_.id;
                        roles = "channel_user"; #とりあえず固定値
                    }
                })
            }
        );
    }
}

$mmUsers | ForEach-Object {[PSCustomObject]@{type="user"; user=$_} | ConvertTo-Json -Compress -EscapeHandling EscapeHtml -Depth 6} | Add-Content -Path $outputFilePath

$mmPosts = @{}

$slackChannels | ForEach-Object {
    $channelName = $_.id
    Get-ChildItem (Join-Path $exportDataPath $_.name) -Filter "*.json" | ForEach-Object {
        $timestamps = @()
        Get-Content $_ | ConvertFrom-Json | ForEach-Object {
            $createAt = [Int64][System.Math]::Round([double][Int64](($_.ts + "0000") -replace "\.(\d{4})\d+","`$1") / 10, [System.MidpointRounding]::AwayFromZero)
            $timestamps += $createAt
            $createAt += ($timestamps | Where-Object {$_ -eq $createAt}).Count - 1
            if ($_.subtype -eq "bot_add") {
                if ($_.text -match "/services/(\w+)\|") {
                    $botOwner[$Matches[1]] = $userTable[$_.user].username
                }
            }
            if ($_.subtype -match "bot_add|channel_join|pinned_item") {return}
            $message = [regex]::Replace($_.text, "<@(\w+)(\|\w+)?>", {$userTable.ContainsKey($args.groups[1].Value) ? "@{0}" -f $userTable[$args.groups[1].Value].username : $args.Value})
            $message = $message -replace "<#\w+\|(\w+)>","~`$1"
            $message = $message -replace "<!here\|@here>","@here" -replace "<!channel>","@channel" -replace "<!everyone>","@all"
            $message = $message -replace "<([^|<>]+)\|([^|<>]+)>","[`$2](`$1)" -replace "(^|[\s.;,])\*(\S[^*\n]+)\*","`$1**`$2**" -replace "(^|[\s.;,])\~(\S[^~\n]+)\~","`$1~~`$2~~" -replace "(?!\n|^)``````","`n``````" -replace "``````(?!\n|$)","```````n"
            $message = [System.Web.HttpUtility]::HtmlDecode($message)
            $props = @{}
            if ($_.attachments -ne $null) {
                $props.attachments = $_.attachments
                $props.attachments | Where-Object {$_.color -ne $null} | ForEach-Object {$_.color = "#{0}" -f $_.color.TrimStart('#')}
            }
            if ($_.subtype -eq "bot_message") {
                $props.from_webhook = "true"
                if ($_.username -ne $null) {
                    $props.override_username = $_.username
                }
                if (($_.icons -ne $null) -and ($_.icons.emoji -ne $null)) {
                    $props.override_icon_emoji = $_.icons.emoji
                }
            }
            $props = $props.Count -eq 0 ? $null : [PSCustomObject]$props
            $reactions = @()
            if ($_.reactions -ne $null) {
                $_.reactions | ForEach-Object {
                    $emoji_name = $_.name
                    $_.users | ForEach-Object {
                        $user = $userTable[$_].username
                        $reactions += [PSCustomObject]@{
                            user = $user;
                            create_at = $createAt + 1;
                            emoji_name = $emoji_name;
                        }
                    }
                }
            }
            $attachments = @()
            if ($_.files -ne $null) {
                $_.files | ForEach-Object {
                    $filename = "{0}_{1}" -f $_.id,$_.name
                    if (-not $jsonlOnly) {
                        Invoke-WebRequest -Uri $_.url_private_download -OutFile (Join-Path $attachmentPath $filename)
                    }
                    $attachments += [PSCustomObject]@{
                        path = "{0}/{1}" -f $attachmentDir,$filename
                    }
                }
            }
            $post = @{
                channel = $channelName;
                message = $message;
                props = $props;
                create_at = $createAt;
                reactions = $reactions;
                attachments = $attachments;
            }
            if ($_.subtype -eq "bot_message") {
                $mmPosts[$_.ts] = [PSCustomObject]($post + @{
                    team = $teamName;
                    user = $botOwner.ContainsKey($_.bot_id) ? $botOwner[$_.bot_id] : $slackUsers[0].name;
                    type = ($_.text -eq "") -and ($_.attachments -ne $null) ? "slack_attachment" : "";
                    replies = @();
                })
            } else {
                if (($_.thread_ts -eq $null) -or ($_.thread_ts -eq $_.ts)) {
                    $mmPosts[$_.ts] = [PSCustomObject]($post + @{
                        team = $teamName;
                        user = $userTable[$_.user].username;
                        replies = @();
                    })
                } else {
                    $mmPosts[$_.thread_ts].replies += [PSCustomObject]($post + @{
                        user = $userTable[$_.user].username;
                    })
                }
            }
        }
    }
}

$mmPosts.Values | ForEach-Object {[PSCustomObject]@{type="post"; post=$_} | ConvertTo-Json -Compress -EscapeHandling EscapeHtml -Depth 7} | Add-Content -Path $outputFilePath

if (-not $jsonlOnly) {
    Compress-Archive -Path $outputFilePath,(Join-Path $outputDataPath "data") -DestinationPath $outputZip -Force
    Remove-Item -Path $outputDataPath -Recurse
}

Remove-Item -Path $exportDataPath -Recurse
