# Fonts/

Drop your brand `.ttf` / `.otf` files here, then:

1. Add each font file to the Xcode target (drag → check "Add to
   target: AppName").
2. Register in `Info.plist` under `UIAppFonts`:
   ```xml
   <key>UIAppFonts</key>
   <array>
     <string>Inter-Regular.ttf</string>
     <string>Inter-Bold.ttf</string>
   </array>
   ```
3. Reference via `Font.custom("Inter-Regular", size: 16)` or the
   `.font(.custom(...))` modifier.

Keep the font list lean — the six-level hierarchy rule from
`mobile-first-density-design` means you almost never need more than
two faces (one display, one body) at two-to-three weights each.
