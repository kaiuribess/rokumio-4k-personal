' Vendored EmojiLabel utilities (Twemoji/EmojiOnRoku) unit tests.
'
' toCodePoint / toURI are pure string and point-math helpers that run fully in
' the interpreter: every card line splits an emoji's code points apart and builds
' the pinned CDN URI for its Twemoji art spot on. Regex matching and the poster
' fetching itself stay a device concern.

sub Test_EmojiUtil_ToCodePointAstral()
    Harness_Suite("toCodePoint combines an astral pair into one hex point")
    Harness_Equal(toCodePoint([&hD83D, &hDE00]), "1f600", "grinning face")
    Harness_Equal(toCodePoint([&hD83C, &hDDFA, &hD83C, &hDDF8]), "1f1fa-1f1f8", "US flag uses one point per region letter")
    Harness_Equal(toCodePoint([&hD83D, &hDC68, &h200D, &hD83D, &hDC69, &h200D, &hD83D, &hDC67]), "1f468-200d-1f469-200d-1f467", "ZWJ family sequence")
end sub

sub Test_EmojiUtil_ToCodePointBmp()
    Harness_Suite("toCodePoint keeps BMP letters and FE0F variation selectors")
    Harness_Equal(toCodePoint([&h2764]), "2764", "plain heart")
    Harness_Equal(toCodePoint([&h2764, &hFE0F]), "2764-fe0f", "heart with variation selector")
    Harness_Equal(toCodePoint([&h2708, &hFE0F]), "2708-fe0f", "airplane with variation selector")
end sub

sub Test_EmojiUtil_ToUriPinned()
    Harness_Suite("toURI points at the pinned jsDelivr twemoji copy")
    Harness_Equal(toURI("1f600"), "https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f600.png", "default 72x72 point URL")
    Harness_Equal(toURI("1f468-200d-1f469-200d-1f467"), "https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f468-200d-1f469-200d-1f467.png", "ZWJ sequence keeps its dashes in the URL")
    Harness_Equal(toURI("1f1fa-1f1f8", "128x128"), "https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/128x128/1f1fa-1f1f8.png", "custom size slot")
end sub