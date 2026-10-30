# The presets, used by presets.ps1 (one preset) and compare-presets.ps1 (all of them).
# Engine 'color' runs remove-background.ps1 (plain backgrounds); 'ai' runs remove-background-ai.ps1 with
# Params.Model = a file in models\ (an AI preset whose model isn't downloaded is skipped by the comparison).
# Params are passed straight to the engine script. Order here = order in the comparison sheet.
[ordered]@{
    'ai' = @{
        Engine      = 'ai'
        Description = 'AI: any background - scenes, rooms, furniture. Renders and photos.'
        Params      = @{ Model = 'isnet-general-use' }
    }
    'ai-anime' = @{
        Engine      = 'ai'
        Description = 'AI for anime / illustration art. Not for 3D renders.'
        Params      = @{ Model = 'isnet-anime' }
    }
    'ai-best' = @{
        Engine      = 'ai'
        Description = 'Most accurate AI (BiRefNet), renders and drawn art. Slow: ~20 s per image on CPU.'
        Params      = @{ Model = 'BiRefNet-general-epoch_244' }
        Slow        = $true
    }
    'flat' = @{
        Engine      = 'color'
        Description = 'Plain one-colour background. Keeps shadows/highlights close to it.'
        Params      = @{}
    }
    'gradient' = @{
        Engine      = 'color'
        Description = 'Background shades across the image (vignette, soft lighting).'
        Params      = @{ FollowGradient = $true }
    }
    'holes' = @{
        Engine      = 'color'
        Description = 'Background shows through gaps in the subject (arms, hair loops).'
        Params      = @{ RemoveEnclosed = $true }
    }
    'gradient-holes' = @{
        Engine      = 'color'
        Description = 'Shaded background that also shows through gaps.'
        Params      = @{ FollowGradient = $true; RemoveEnclosed = $true }
    }
    'sprite' = @{
        Engine      = 'color'
        Description = 'Pixel art / icons on an exact key colour. Hard edges.'
        Params      = @{ RemoveEnclosed = $true; Softness = 0 }
    }
}
