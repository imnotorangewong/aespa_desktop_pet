-- The caller passes metadata as arguments, including names containing quotes or newlines.
on locateTrack(trackID, songTitle, artistName, albumName)
    tell application id "com.apple.Music"
        if trackID is not "" then
            try
                if persistent ID of current track is trackID then return current track
            end try
            repeat with scopeName in {"library", "queue", "application"}
                try
                    if contents of scopeName is "library" then
                        set candidates to (every track of library playlist 1 whose persistent ID is trackID)
                    else if contents of scopeName is "queue" then
                        set candidates to (every track of current playlist whose persistent ID is trackID)
                    else
                        set candidates to (every track whose persistent ID is trackID)
                    end if
                    if (count candidates) > 0 then
                        set candidate to item 1 of candidates
                        if persistent ID of candidate is trackID then return candidate
                    end if
                on error number errCode
                    if errCode is not -1728 then error number errCode
                end try
            end repeat
        end if
        if songTitle is "" or artistName is "" then return missing value
        repeat with scopeName in {"library", "queue", "application"}
            try
                if contents of scopeName is "library" then
                    set candidates to (every track of library playlist 1 whose name is songTitle and artist is artistName)
                else if contents of scopeName is "queue" then
                    set candidates to (every track of current playlist whose name is songTitle and artist is artistName)
                else
                    set candidates to (every track whose name is songTitle and artist is artistName)
                end if
                set foundTrack to missing value
                repeat with candidate in candidates
                    if albumName is "" or album of candidate is albumName then
                        if foundTrack is not missing value then
                            if persistent ID of foundTrack is not persistent ID of candidate then error "ambiguous" number 17001
                        end if
                        set foundTrack to contents of candidate
                    end if
                end repeat
                if foundTrack is not missing value then return foundTrack
            on error number errCode
                if errCode is not -1728 then error number errCode
            end try
        end repeat
        return missing value
    end tell
end locateTrack

on run argv
    set {operation, trackID, songTitle, artistName, albumName, outputPath} to argv
    with timeout of 12 seconds
        if operation is "confirm" then
            tell application id "com.apple.Music"
                repeat 24 times
                    try
                        set playingTrack to current track
                        if player state is playing and name of playingTrack is songTitle and artist of playingTrack is artistName and (albumName is "" or album of playingTrack is albumName) then return "playing"
                    end try
                    delay 0.25
                end repeat
            end tell
            return "unconfirmed"
        end if
        set chosenTrack to missing value
        if operation is "catalog" or operation is "open-catalog" then
            tell application id "com.apple.Music"
                open location outputPath
                activate
                if operation is "open-catalog" then return "catalog-open"
                -- Music versions differ in whether a catalog deep link exposes a scriptable selection.
                repeat 8 times
                    delay 0.25
                    try
                        set picked to selection
                        if (count picked) is 1 then
                            set candidate to item 1 of picked
                            if name of candidate is songTitle and artist of candidate is artistName and (albumName is "" or album of candidate is albumName) then
                                set chosenTrack to candidate
                                exit repeat
                            end if
                        end if
                    end try
                end repeat
            end tell
            if chosenTrack is missing value then return "catalog-open"
            set operation to "play"
        else
            try
                set chosenTrack to my locateTrack(trackID, songTitle, artistName, albumName)
            on error number 17001
                return "ambiguous"
            end try
        end if
        if chosenTrack is missing value then return "missing"
        tell application id "com.apple.Music"
            if operation is "resolve" then return "matched"
            if operation is "play" then
                set chosenID to persistent ID of chosenTrack
                set chosenName to name of chosenTrack
                set chosenArtist to artist of chosenTrack
                set chosenAlbum to album of chosenTrack
                play chosenTrack once true
                activate
                repeat 16 times
                    try
                        if player state is playing then
                            set playingTrack to current track
                            if persistent ID of playingTrack is chosenID or (name of playingTrack is chosenName and artist of playingTrack is chosenArtist and album of playingTrack is chosenAlbum) then
                                try
                                    reveal chosenTrack
                                end try
                                return "playing"
                            end if
                        end if
                    end try
                    delay 0.25
                end repeat
                return "unconfirmed"
            end if
            if operation is "picture" then
                try
                    set art to data of artwork 1 of chosenTrack
                on error
                    return "no-cover"
                end try
            else if operation is "cover" then
                try
                    set art to raw data of artwork 1 of chosenTrack
                on error
                    return "no-cover"
                end try
            else
                error "Unknown calendar operation"
            end if
        end tell
        if art is missing value then return "no-cover"
        set dest to open for access (POSIX file outputPath) with write permission
        try
            set eof dest to 0
            write art to dest
            close access dest
        on error msg number code
            close access dest
            error msg number code
        end try
        return "cover"
    end timeout
end run
