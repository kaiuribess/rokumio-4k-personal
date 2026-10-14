function AccountEpoch_Read(top as dynamic) as integer
    try
        scene = top.GetScene()
        if scene <> invalid and scene.HasField("accountGeneration") then return scene.accountGeneration
    catch e
    end try
    return 0
end function
