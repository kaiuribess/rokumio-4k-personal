' One featured image; no video preview, media probe or metadata request on focus.
sub HomeCinema_Init()
    m.quick=m.top.FindNode("homeQuick")
    m.heroArt=m.top.FindNode("homeHeroArt")
    m.heroMark=m.top.FindNode("homeHeroMark")
    m.heroTitle=m.top.FindNode("homeHeroTitle")
    m.heroInfo=m.top.FindNode("homeHeroInfo")
    m.heroOverview=m.top.FindNode("homeHeroOverview")
    m.heroTimer=m.top.FindNode("homeHeroDelay")
    m.heroPanel=m.top.FindNode("homeHeroPanel")
    m.heroTimer.ObserveField("fire","HomeCinema_OnHeroDelay")
    m.catalog.ObserveField("rowItemFocused","HomeCinema_OnPosterFocus")
    m.quick.ObserveField("rowItemSelected","HomeCinema_OnQuickSelected")
    m.heroArt.ObserveField("loadStatus","HomeCinema_OnArtStatus")
    m.quickBuilt=false:m.heroSignature="":m.heroPending=false:m.homeBrowse=false
    t=Theme()
    m.top.FindNode("homeHeroFace").color=t.tileFace
    m.top.FindNode("homeHeroAccent").color=t.accent
    m.heroTitle.color=t.textPrimary:m.heroInfo.color=t.accentFocus:m.heroOverview.color=t.textSecondary
end sub

sub HomeCinema_OnEnter()
    if m.quick=invalid then return
    if not m.quickBuilt
        m.quickEntries=[{title:"Search",detail:"Type or use your microphone",screen:"searchScreen",params:{}},{title:"Movies",detail:"Popular and new titles",screen:"discoverScreen",params:{metaType:"movie"}},{title:"Shows",detail:"Series and episodes",screen:"discoverScreen",params:{metaType:"series"}},{title:"Genres",detail:"Find your kind of movie",screen:"discoverScreen",params:{focusGenres:true}},{title:"My list",detail:"Saved and watched titles",screen:"libraryScreen",params:{}}]
        content=CreateObject("roSGNode","ContentNode")
        row=content.CreateChild("ContentNode")
        for each entry in m.quickEntries
            item=row.CreateChild("ContentNode"):item.title=entry.title:item.description=entry.detail
        end for
        m.quick.content=content:m.quickBuilt=true
    end if
    HomeCinema_Browse(m.returnFocus="catalog" and m.gridRows.Count()>0)
end sub

sub HomeCinema_OnQuickSelected()
    data=m.quick.rowItemSelected
    if Type(data)<>"roArray" or data.Count()<2 then return
    index=data[1]
    if index<0 or index>=m.quickEntries.Count() then return
    entry=m.quickEntries[index]
    m.top.pushRequest={screen:entry.screen,params:entry.params}
end sub

function HomeCinema_Key(key as string) as boolean
    if m.quick=invalid then return false
    if key="options"
        if m.quick.HasFocus()
            if m.gridRows.Count()>0 then HomeCinema_Browse(true):m.returnFocus="catalog":m.catalog.SetFocus(true) else m.returnFocus="rail":m.rail.SetFocus(true)
        else if m.catalog.HasFocus()
            HomeCinema_Browse(false):m.returnFocus="rail":m.rail.SetFocus(true)
        else
            m.returnFocus="quick":m.quick.SetFocus(true)
        end if
        return true
    end if
    if key="right" and m.rail.HasFocus() then m.returnFocus="quick":m.quick.SetFocus(true):return true
    if key="down" and m.quick.HasFocus()
        if m.gridRows.Count()>0 then HomeCinema_Browse(true):m.returnFocus="catalog":m.catalog.SetFocus(true)
        return true
    end if
    if key="up" and m.catalog.HasFocus()
        pair=m.catalog.rowItemFocused
        if Type(pair)="roArray" and pair.Count()>0
            if pair[0]=0 then HomeCinema_Browse(false):m.returnFocus="quick":m.quick.SetFocus(true):return true
        end if
    end if
    if key="left" and m.quick.HasFocus() then m.returnFocus="rail":m.rail.SetFocus(true):return true
    if key="left" and m.catalog.HasFocus() then HomeCinema_Browse(false):m.returnFocus="rail":m.rail.SetFocus(true):return true
    return false
end function

sub HomeCinema_Browse(expanded as boolean)
    if m.quick=invalid then return
    m.homeBrowse=expanded
    if m.heroPanel<>invalid then m.heroPanel.visible=not expanded
    if expanded
        m.quick.translation=[260,164]:m.catalog.translation=[260,292]:m.catalog.itemSpacing=[0,48]
        if m.catalogStatus<>invalid then m.catalogStatus.visible=false
        if m.heroArt<>invalid then m.heroArt.uri=""
        m.heroPending=false:m.heroSignature=""
        if m.heroTimer<>invalid then m.heroTimer.control="stop"
    else
        m.quick.translation=[260,462]:m.catalog.translation=[260,628]:m.catalog.itemSpacing=[0,64]
        if m.catalogStatus<>invalid then m.catalogStatus.translation=[260,570]:m.catalogStatus.visible=true
    end if
    m.catalog.numRows=HomeVisibleRows(m.gridRows.Count())
    if not expanded then HomeCinema_RefreshHero()
end sub

sub HomeCinema_OnPosterFocus()
    if m.heroTitle=invalid or m.top.screenActive<>true then return
    if m.homeBrowse=true then return
    m.heroPending=true
    m.heroGuard=TimerGuard_Start(m.heroTimer,250)
end sub

sub HomeCinema_OnHeroDelay()
    if m.heroPending<>true or m.top.screenActive<>true then return
    if not TimerGuard_Ready(m.heroTimer,m.heroGuard) then return
    m.heroPending=false
    HomeCinema_RefreshHero()
end sub

sub HomeCinema_Blur()
    m.heroPending=false
    if m.heroTimer<>invalid then m.heroTimer.control="stop"
    if m.heroArt<>invalid then m.heroArt.uri=""
    m.heroSignature=""
end sub

sub HomeCinema_OnArtStatus()
    if m.heroArt=invalid or m.heroMark=invalid then return
    m.heroMark.visible=m.heroArt.loadStatus<>"ready"
end sub

sub HomeCinema_RefreshHero()
    if m.heroTitle=invalid then return
    if m.homeBrowse=true then return
    title="Your next movie night"
    info="Movies, shows and your saved favorites"
    overview="Search, browse a category, or pick up where you left off. Your add-ons supply available titles and streams."
    art=""
    if Type(m.gridRows)="roArray" and m.gridRows.Count()>0
        rowIndex=0:column=0
        pair=m.catalog.rowItemFocused
        if Type(pair)="roArray" and pair.Count()>1 then rowIndex=pair[0]:column=pair[1]
        if rowIndex<0 or rowIndex>=m.gridRows.Count() then rowIndex=0
        row=m.gridRows[rowIndex]
        if Type(row.metas)="roArray" and row.metas.Count()>0
            if row.browse=true and column=row.metas.Count()
                title=row.title:info="Explore the full catalog":overview="Open See all for the complete category, genre filters and more pages."
            else
                if column<0 or column>=row.metas.Count() then column=0
                meta=row.metas[column]
                title=HomeCatalog_Text(meta.name)
                info=HomeCatalog_Text(row.title)
                year=HomeCatalog_Text(meta.releaseInfo)
                if year<>"" then info=info+" · "+year
                overview=HomeCatalog_Text(meta.homeOverview)
                if overview="" then overview="Open this title for details, episodes and available source choices."
                art=HomeCatalog_Text(meta.background)
                if art="" then art=HomeCatalog_Text(meta.poster)
            end if
        end if
    end if
    signature=FormatJson({title:title,info:info,overview:overview,art:art})
    if signature=m.heroSignature then return
    m.heroSignature=signature
    m.heroTitle.text=title.Left(160):m.heroInfo.text=info.Left(120):m.heroOverview.text=overview.Left(280)
    if m.heroArt.uri<>art then m.heroArt.uri=art
    HomeCinema_OnArtStatus()
end sub

sub HomeCinema_OpenCatalog(row as object)
    m.top.pushRequest={screen:"discoverScreen",params:{addonAddress:row.addonAddress,catalogId:row.catalogId,metaType:row.metaType,genre:row.genre}}
end sub
