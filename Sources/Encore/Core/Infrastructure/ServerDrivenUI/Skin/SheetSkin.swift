// Publisher skin for the reward sheet: a pure rewrite of the raw template before decode.
// A port of web-sdk src/sdui/skin.ts; contract in backend docs/architecture/sdui-sheet-skin.md.

import Foundation

enum SkinScheme: String { case light, dark }

enum SkinColor: Equatable {
    case plain(String)
    case pair(light: String, dark: String)
}

/// A Lottie file for an `asyncImage`, with the still it draws without one.
struct SkinAnimation: Equatable {
    var url: String
    var fallbackImage: String
    var loop: Bool?
    var autoplay: Bool?
    /// The valid `images` slots, as served.
    var images: SkinMotion?
}

/// A checked `enter` or `loop` value, kept as JSON so the rewrite writes exactly what was served.
struct SkinMotion: Equatable {
    let json: SkinJSON
    static func == (a: SkinMotion, b: SkinMotion) -> Bool { a.json.sameValue(as: b.json) }
}

/// One component's properties after lenient reading: only values of the right type and range.
struct SkinComponentStyle: Equatable {
    var fill: SkinColor?
    var cornerRadius: Double?
    var borderWidth: Double?
    var borderColor: SkinColor?
    var contentColor: SkinColor?
    var font: SheetComponentStyle.FontRole?
    var image: String?
    var trueImage: String?
    var falseImage: String?
    var backgroundImage: String?
    var animation: SkinAnimation?
    var enter: SkinMotion?
    var loop: SkinMotion?

    var isEmpty: Bool { self == SkinComponentStyle() }

    /// `self` over `base`, per property.
    func over(_ base: SkinComponentStyle) -> SkinComponentStyle {
        // `image` and `animation` are one slot (the animation's still is the image): a side that sets either wins both.
        let slotIsMine = image != nil || animation != nil
        return SkinComponentStyle(
            fill: fill ?? base.fill, cornerRadius: cornerRadius ?? base.cornerRadius, borderWidth: borderWidth ?? base.borderWidth,
            borderColor: borderColor ?? base.borderColor, contentColor: contentColor ?? base.contentColor, font: font ?? base.font,
            image: slotIsMine ? image : base.image, trueImage: trueImage ?? base.trueImage, falseImage: falseImage ?? base.falseImage,
            backgroundImage: backgroundImage ?? base.backgroundImage, animation: slotIsMine ? animation : base.animation,
            enter: enter ?? base.enter, loop: loop ?? base.loop
        )
    }

    /// Every image URL, for the prefetch.
    var imageURLs: [String] { [image, trueImage, falseImage, backgroundImage, animation?.fallbackImage].compactMap { $0 } }
}

/// A served skin after lenient reading.
struct SheetSkin {
    var id: String?
    var components: [String: SkinComponentStyle] = [:]
}

struct ResolvedSheetSkin {
    var id: String?
    var components: [String: SkinComponentStyle]
    /// The app's family for each role; a role with none draws the system font.
    var fonts: [SheetComponentStyle.FontRole: String]

    var fontFlags: SheetSkinApplier.Fonts { .init(heading: fonts[.heading] != nil, body: fonts[.body] != nil) }
}

// MARK: - Reading

enum SheetSkinReader {
    /// What `font.family` holds after the rewrite; the renderer resolves a role to a face when it draws.
    static func family(_ role: SheetComponentStyle.FontRole) -> String { "encore:\(role.rawValue)" }

    private static let colorProps = ["fill", "borderColor", "contentColor"]
    private static let imageProps = ["image", "trueImage", "falseImage", "backgroundImage"]
    private static let lengthLimits: [String: Double] = ["cornerRadius": 999, "borderWidth": 8]

    static func isHex(_ value: String) -> Bool {
        let chars = Array(value)
        guard chars.first == "#", chars.count == 7 || chars.count == 9 else { return false }
        return chars.dropFirst().allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    static func readColor(_ value: SkinJSON) -> SkinColor? {
        if let s = value.string { return isHex(s) ? .plain(s) : nil }
        if let o = value.object, let light = o["light"]?.string, let dark = o["dark"]?.string {
            return isHex(light) && isHex(dark) ? .pair(light: light, dark: dark) : nil
        }
        return nil
    }

    /// Six digits, or eight ending in FF; a pair only when both halves are.
    static func isOpaque(_ color: SkinColor) -> Bool {
        func solid(_ hex: String) -> Bool { hex.count == 7 || hex.dropFirst(7).uppercased() == "FF" }
        switch color {
        case .plain(let hex): return solid(hex)
        case .pair(let light, let dark): return solid(light) && solid(dark)
        }
    }

    static func readImage(_ value: SkinJSON?) -> String? {
        guard let s = value?.string, s.lowercased().hasPrefix("https://"), s.count > 8,
              !s.contains(where: { $0.isWhitespace }) else { return nil }
        return s
    }

    /// One component's properties, dropping (with a warning) any value that is unknown, mistyped or out of range.
    static func readComponentStyle(_ name: String, _ raw: SkinJSON, warn: (String) -> Void) -> SkinComponentStyle {
        var style = SkinComponentStyle()
        guard let object = raw.object else {
            warn("skin component \(name) is not an object; ignored")
            return style
        }
        for (key, value) in object.entries {
            if colorProps.contains(key) {
                guard let color = readColor(value) else { warn("skin \(name).\(key) is not a colour; ignored"); continue }
                // The close X must never be invisible: its colour is opaque or nothing.
                if name == "closeButton", key == "contentColor", !isOpaque(color) {
                    warn("skin closeButton.contentColor must be opaque; ignored")
                    continue
                }
                switch key {
                case "fill": style.fill = color
                case "borderColor": style.borderColor = color
                default: style.contentColor = color
                }
            } else if let max = lengthLimits[key] {
                guard let n = value.number, n.isFinite, n >= 0, n <= max else {
                    warn("skin \(name).\(key) must be a number from 0 to \(Int(max)); ignored")
                    continue
                }
                if key == "cornerRadius" { style.cornerRadius = n } else { style.borderWidth = n }
            } else if key == "font" {
                guard let role = value.string.flatMap(SheetComponentStyle.FontRole.init(rawValue:)) else {
                    warn("skin \(name).font must be \"heading\" or \"body\"; ignored")
                    continue
                }
                style.font = role
            } else if imageProps.contains(key) {
                guard let url = readImage(value) else { warn("skin \(name).\(key) is not an https URL; ignored"); continue }
                switch key {
                case "image": style.image = url
                case "trueImage": style.trueImage = url
                case "falseImage": style.falseImage = url
                default: style.backgroundImage = url
                }
            } else if key == "animation" {
                switch readAnimation(value) {
                case .success(let animation):
                    style.animation = animation
                    if let images = value.object?["images"] {
                        for problem in SheetMotionRules.imageSlots(images).problems { warn("skin \(name).animation \(problem); ignored") }
                    }
                case .failure(let problem): warn("skin \(name).animation \(problem.reason); ignored")
                }
            } else if key == "enter" || key == "loop" {
                if let problem = key == "enter" ? SheetMotionRules.enterProblem(value) : SheetMotionRules.sheetLoopProblem(value) {
                    warn("skin \(name).\(key) \(problem); ignored")
                    continue
                }
                // A skin styles; it never moves the sheet on (backend skinProblems refuses these too).
                let copy = value.deepCopy()
                if let motion = copy.object {
                    for flow in skinFlowKeys where motion[flow] != nil {
                        warn("skin \(name).\(key).\(flow) changes the flow, which a skin never does; ignored")
                        motion[flow] = nil
                    }
                }
                if key == "enter" { style.enter = SkinMotion(json: copy) } else { style.loop = SkinMotion(json: copy) }
            } else {
                warn("skin \(name).\(key) is not a skin property; ignored")
            }
        }
        return style
    }

    /// Sheet keys that change the flow or the screen (sdui-sheet-motion.md, layer 3); a skin never carries them.
    static let skinFlowKeys = ["onComplete", "fallbackSeconds", "after", "exit", "persistKey", "transition"]

    /// A served motion or animation with a completion, which a skin value never replaces.
    static func carriesFlow(_ value: SkinJSON?) -> Bool {
        guard let completion = value?.object?["onComplete"] else { return false }
        if case .null = completion { return false }
        return true
    }

    struct Problem: Error { let reason: String }

    /// A skin `animation`, or why it cannot be used.
    static func readAnimation(_ value: SkinJSON) -> Result<SkinAnimation, Problem> {
        guard let object = value.object else { return .failure(Problem(reason: "must be an object")) }
        guard let url = readImage(object["url"]) else { return .failure(Problem(reason: "url is not an https URL")) }
        guard let still = readImage(object["fallbackImage"]) else { return .failure(Problem(reason: "fallbackImage is not an https URL")) }
        if let flags = SheetMotionRules.animationFlagsProblem(object) { return .failure(Problem(reason: flags)) }
        func flag(_ key: String) -> Bool? { if case .bool(let b)? = object[key] { return b } else { return nil } }
        var images: SkinMotion?
        if let raw = object["images"], let served = raw.object {
            // Only the slots the sheet decoder keeps; each other one is warned about by the caller.
            let valid = SheetMotionRules.imageSlots(raw).slots
            let kept = SkinObject(served.entries.filter { valid[$0.key] != nil }.map { ($0.key, $0.value.deepCopy()) })
            if kept.count > 0 { images = SkinMotion(json: .object(kept)) }
        }
        return .success(SkinAnimation(url: url, fallbackImage: still, loop: flag("loop"), autoplay: flag("autoplay"), images: images))
    }

    /// Reads the served `values.skin` leniently. Never throws; anything unreadable is dropped with a warning.
    static func readSkin(_ raw: SkinJSON?, warn: (String) -> Void) -> SheetSkin {
        var skin = SheetSkin()
        guard let raw else { return skin }
        if case .null = raw { return skin }
        guard let object = raw.object else {
            warn("skin is not an object; ignored")
            return skin
        }
        skin.id = object["id"]?.string
        // Fonts come from app code only (AppearanceConfig.sheet); an older skin may still carry them.
        if object["fonts"] != nil { warn("skin fonts are set in app code (appearance.sheet); ignored") }
        if object["components"] != nil, object["components"]?.object == nil { warn("skin components is not an object; ignored") }
        if let components = object["components"]?.object {
            for (name, value) in components.entries { skin.components[name] = readComponentStyle(name, value, warn: warn) }
        }
        return skin
    }

    /// Portal over app code, per property: a property the portal skin leaves unset takes the app value.
    static func mergeComponents(_ app: [String: SkinComponentStyle], _ portal: [String: SkinComponentStyle]) -> [String: SkinComponentStyle] {
        var out = app
        for (name, style) in portal { out[name] = style.over(app[name] ?? SkinComponentStyle()) }
        return out
    }

    static func isEmptySkin(_ components: [String: SkinComponentStyle], fonts: SheetSkinApplier.Fonts) -> Bool {
        !fonts.heading && !fonts.body && components.values.allSatisfy(\.isEmpty)
    }

    /// The advertiser's own content, which app code never restyles: its name and detail text, and its logo image or animation.
    static let appLockedComponents: Set<String> = ["offerTitle", "offerDetail"]

    static func withoutAdvertiserContent(_ name: String, _ style: SkinComponentStyle, warn: (String) -> Void) -> SkinComponentStyle {
        let locked = "is the advertiser's content and is not editable; ignored"
        if appLockedComponents.contains(name) {
            if !style.isEmpty { warn("appearance.sheet \(name) \(locked)") }
            return SkinComponentStyle()
        }
        var kept = style
        if name == "offerLogo", kept.image != nil {
            kept.image = nil
            warn("appearance.sheet offerLogo.image \(locked)")
        }
        // The animation's still would replace the logo just as `image` does.
        if name == "offerLogo", kept.animation != nil {
            kept.animation = nil
            warn("appearance.sheet offerLogo.animation \(locked)")
        }
        return kept
    }

    /// Portal skin over app code, per property. Fonts are app code's only. Never throws.
    static func resolveSheetSkin(_ app: SheetAppearance?, portal portalRaw: SkinJSON?, warn: (String) -> Void) -> ResolvedSheetSkin {
        let portal = readSkin(portalRaw, warn: warn)
        var appComponents: [String: SkinComponentStyle] = [:]
        // Sorted by name: a dictionary has no app order, and warnings should come out the same every run.
        for (component, style) in (app?.components ?? [:]).sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let read = readComponentStyle(component.rawValue, style.json, warn: warn)
            appComponents[component.rawValue] = withoutAdvertiserContent(component.rawValue, read, warn: warn)
        }
        var fonts: [SheetComponentStyle.FontRole: String] = [:]
        for role in [SheetComponentStyle.FontRole.heading, .body] {
            let family = (role == .heading ? app?.headingFontFamily : app?.bodyFontFamily)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let family, !family.isEmpty { fonts[role] = family }
        }
        return ResolvedSheetSkin(id: portal.id, components: mergeComponents(appComponents, portal.components), fonts: fonts)
    }
}

extension SheetComponentStyle {
    /// The wire shape, so app values pass the same lenient reading as served ones.
    var json: SkinJSON {
        var pairs: [(String, SkinJSON)] = []
        func number(_ v: CGFloat?) -> SkinJSON? { v.map { .number(Double($0)) } }
        let fields: [(String, SkinJSON?)] = [
            ("fill", fill?.json), ("cornerRadius", number(cornerRadius)), ("borderWidth", number(borderWidth)),
            ("borderColor", borderColor?.json), ("contentColor", contentColor?.json),
            ("font", font.map { .string($0.rawValue) }), ("image", image.map { .string($0.absoluteString) }),
            ("trueImage", trueImage.map { .string($0.absoluteString) }), ("falseImage", falseImage.map { .string($0.absoluteString) }),
            ("backgroundImage", backgroundImage.map { .string($0.absoluteString) }),
            ("animation", animation.map(\.json)), ("enter", enter.map(\.json)), ("loop", loop.map(\.json)),
        ]
        for (key, value) in fields { if let value { pairs.append((key, value)) } }
        return .object(SkinObject(pairs))
    }
}

extension SkinAnimation {
    /// What `asyncImage.animation` takes: the file and only the flags given.
    var variantJSON: SkinJSON {
        var pairs: [(String, SkinJSON)] = [("url", .string(url))]
        if let loop { pairs.append(("loop", .bool(loop))) }
        if let autoplay { pairs.append(("autoplay", .bool(autoplay))) }
        if let images { pairs.append(("images", images.json.deepCopy())) }
        return .object(SkinObject(pairs))
    }
}

// MARK: - App motion as skin JSON

extension SheetAnimation {
    /// The skin's `animation` JSON, so app values take the portal's path.
    var json: SkinJSON {
        var pairs: [(String, SkinJSON)] = [("url", .string(url.absoluteString)), ("fallbackImage", .string(fallbackImage.absoluteString))]
        if let loop { pairs.append(("loop", .bool(loop))) }
        if let autoplay { pairs.append(("autoplay", .bool(autoplay))) }
        if let images {
            let slots = images.sorted { $0.key < $1.key }.map { key, slot -> (String, SkinJSON) in
                (key, .object(SkinObject([("offer", .number(Double(slot.offer))), ("urlBinding", .string(slot.picture.urlBinding))])))
            }
            pairs.append(("images", .object(SkinObject(slots))))
        }
        return .object(SkinObject(pairs))
    }
}

extension SheetOfferPicture {
    /// The binding an `asyncImage` uses for the same picture.
    var urlBinding: String {
        switch self {
        case .logo: return "offerLogoImage"
        case .hero: return "offerHeroImage"
        case .primaryCreative: return "offerPrimaryCreative"
        }
    }
}

extension SheetPose {
    /// The pose keys of `style.enter.from` and a loop keyframe; one offset set writes both.
    var pairs: [(String, SkinJSON)] {
        var out: [(String, SkinJSON)] = []
        if let scale { out.append(("scale", .number(scale))) }
        if let opacity { out.append(("opacity", .number(opacity))) }
        if let rotation { out.append(("rotation", .number(rotation))) }
        if offsetX != nil || offsetY != nil {
            out.append(("offset", .object(SkinObject([("x", .number(offsetX ?? 0)), ("y", .number(offsetY ?? 0))]))))
        }
        return out
    }

    var json: SkinJSON { .object(SkinObject(pairs)) }
}

extension SheetEnter {
    var json: SkinJSON {
        var pairs: [(String, SkinJSON)] = [("from", from.json), ("duration", .number(duration))]
        if let delay { pairs.append(("delay", .number(delay))) }
        if let curve { pairs.append(("curve", .string(curve.rawValue))) }
        return .object(SkinObject(pairs))
    }
}

extension SheetLoop {
    var json: SkinJSON {
        var pairs: [(String, SkinJSON)] = [
            ("duration", .number(duration)),
            ("keyframes", .array(keyframes.map { .object(SkinObject([("at", .number($0.at))] + $0.pose.pairs)) })),
        ]
        if let curve { pairs.append(("curve", .string(curve.rawValue))) }
        if let phaseOffset { pairs.append(("phaseOffset", .number(phaseOffset))) }
        if let reducedMotion { pairs.append(("reducedMotion", reducedMotion.json)) }
        if let delay { pairs.append(("delay", .number(delay))) }
        if let repeatCount { pairs.append(("repeatCount", .number(Double(repeatCount)))) }
        return .object(SkinObject(pairs))
    }
}

extension SheetColor {
    /// One hex as a string, a pair as `{ light, dark }`: the two shapes a served colour takes.
    var json: SkinJSON {
        light == dark ? .string(light) : .object(SkinObject([("light", .string(light)), ("dark", .string(dark))]))
    }
}

// MARK: - Applying

enum SheetSkinApplier {
    struct Fonts: Equatable {
        var heading: Bool
        var body: Bool
    }

    struct Options {
        var scheme: SkinScheme
        /// Which font roles have an app family. Only `body` matters here: it turns on the sweep over all other text.
        var fonts: Fonts
        /// The SDK's own spoken label for a button's icon (a symbol name or a glyph) and action type,
        /// kept when the icon becomes an image.
        var iconLabel: (_ icon: String, _ action: String?) -> String?
        var warn: (String) -> Void
    }

    /// The sheet's element names, as web's `ELEMENT_SET`.
    static let elements: Set<String> = [
        "text", "systemImage", "asyncImage", "asyncVideo", "appIcon", "button", "vStack", "hStack", "zStack", "spacer",
        "shape", "gradient", "scrollView", "forEach", "conditional", "group", "textField", "toggle", "slideButton",
        "compactPageIndicator", "confetti", "empty",
    ]
    /// Elements that take no `style`, so no fill, corner or border lands on them.
    private static let styleless: Set<String> = ["conditional", "forEach", "spacer"]

    /// Applies a merged skin to a copy of a raw sheet template; the input is never changed.
    /// Call it only for a non-empty skin, so an unskinned sheet keeps the served template.
    static func applySkin(_ template: SkinJSON, components: [String: SkinComponentStyle], options: Options) -> SkinJSON {
        let root = template.deepCopy()
        if options.fonts.body {
            eachElement(root) { _, kind, props in
                if kind == "text" { setFamily(props, .body) }
                return true
            }
        }
        var pending: [(host: SkinObject, name: String, color: SkinColor)] = []
        func walk(_ node: SkinJSON, _ overlayHost: SkinObject?) {
            if case .array(let items) = node { items.forEach { walk($0, overlayHost) }; return }
            guard let object = node.object else { return }
            guard let (kind, props) = elementOf(object) else {
                object.entries.forEach { walk($0.value, overlayHost) }
                return
            }
            // Children first, so a host's own corner change sees its layers after their own entries.
            for (key, value) in props.entries {
                if key == "style", let style = value.object {
                    for (styleKey, styleValue) in style.entries { walk(styleValue, styleKey == "overlay" ? props : overlayHost) }
                } else {
                    walk(value, overlayHost)
                }
            }
            if let name = props["component"]?.string, let entry = components[name] {
                applyComponent(object, kind, props, entry, name, overlayHost, options, &pending, components)
            }
        }
        walk(root, nil)
        for item in pending { moveOverlayFill(item.host, item.name, item.color, options.scheme) }
        return root
    }

    // MARK: Tree helpers

    /// The single element key of a wrapper such as `{"button": {...}}`.
    static func elementOf(_ node: SkinObject) -> (kind: String, props: SkinObject)? {
        guard node.count == 1, let key = node.keys.first, elements.contains(key), let props = node[key]?.object else { return nil }
        return (key, props)
    }

    /// Every element wrapper under `node`, depth first; `visit` returns false to skip what is inside one.
    static func eachElement(_ node: SkinJSON, _ visit: (SkinObject, String, SkinObject) -> Bool) {
        if case .array(let items) = node { items.forEach { eachElement($0, visit) }; return }
        guard let object = node.object else { return }
        if let (kind, props) = elementOf(object) {
            guard visit(object, kind, props) else { return }
            eachElement(.object(props), visit)
            return
        }
        object.entries.forEach { eachElement($0.value, visit) }
    }

    private static func isTagged(_ props: SkinObject) -> Bool { props["component"]?.string != nil }

    /// Untagged `text` and `systemImage` inside `props`, not entering a tagged element (its own entry governs it).
    private static func eachUntaggedLeaf(_ props: SkinObject, _ fn: (String, SkinObject) -> Void) {
        for (_, value) in props.entries {
            eachElement(value) { _, kind, child in
                if isTagged(child) { return false }
                if kind == "text" || kind == "systemImage" { fn(kind, child) }
                return true
            }
        }
    }

    private static func styleOf(_ props: SkinObject) -> SkinObject {
        if let style = props["style"]?.object { return style }
        let style = SkinObject()
        props["style"] = .object(style)
        return style
    }

    /// A text's colour, and each `segments` run's, so a segmented line takes the colour too.
    private static func colorLeaf(_ leaf: SkinObject, _ color: SkinColor, _ scheme: SkinScheme) {
        leaf["color"] = colorJSON(color, scheme)
        if case .array(let runs)? = leaf["segments"] {
            for case .object(let run) in runs { run["color"] = colorJSON(color, scheme) }
        }
    }

    /// A skinned page indicator's other dots: its colour at this opacity, the alpha of the default inactive dot (tertiaryLabel).
    static let inactiveDotOpacity: Double = 0.3

    private static func colorDots(_ props: SkinObject, _ color: SkinColor, _ scheme: SkinScheme) {
        let active = colorJSON(color, scheme)
        props["activeColor"] = active
        guard let inactive = colorJSON(color, scheme).object else { return }
        let alpha = active.object?["opacity"]?.number ?? 1
        inactive["opacity"] = .number((alpha * inactiveDotOpacity * 1000).rounded() / 1000)
        props["inactiveColor"] = .object(inactive)
    }

    private static func setFamily(_ text: SkinObject, _ role: SheetComponentStyle.FontRole) {
        text["font"]?.object?["family"] = .string(SheetSkinReader.family(role))
    }

    static func colorJSON(_ color: SkinColor, _ scheme: SkinScheme) -> SkinJSON {
        let hex: String
        switch color {
        case .plain(let value): hex = value
        case .pair(let light, let dark): hex = scheme == .light ? light : dark
        }
        // Six digits plus opacity, never eight: a variant's 8-digit hex reads as ARGB here.
        let chars = Array(hex)
        let out = SkinObject([("hex", .string("#" + String(chars[1..<7]).uppercased()))])
        if chars.count == 9, let alpha = Int(String(chars[7..<9]), radix: 16), alpha != 255 {
            out["opacity"] = .number((Double(alpha) / 255 * 1000).rounded() / 1000)
        }
        return .object(out)
    }

    private static func asyncImage(_ url: String, _ size: Double?) -> SkinObject {
        let props = SkinObject([("url", .string(url)), ("contentMode", .string("fit"))])
        if let size {
            props["style"] = .object(SkinObject([("frame", .object(SkinObject([("width", .number(size)), ("height", .number(size))])))]))
        }
        return SkinObject([("asyncImage", .object(props))])
    }

    private static func frameSide(_ props: SkinObject) -> Double? {
        guard let frame = props["style"]?.object?["frame"]?.object else { return nil }
        if let width = frame["width"]?.number { return width }
        return frame["height"]?.number
    }

    /// A deep copy with every `component` tag removed, so a fallback is never skinned a second time.
    private static func untagged(_ node: SkinObject) -> SkinObject {
        let copy = node.deepCopy()
        eachElement(.object(copy)) { _, _, props in
            props["component"] = nil
            return true
        }
        return copy
    }

    /// The size of a branch: its own frame, else the first sized element inside it.
    private static func branchSide(_ branch: SkinObject) -> Double? {
        var side: Double?
        eachElement(.object(branch)) { _, _, props in
            if side != nil { return false }
            side = frameSide(props)
            return side == nil
        }
        return side
    }

    private static func iconSide(_ kind: String, _ props: SkinObject) -> Double? {
        if let framed = frameSide(props) { return framed }
        if let size = props["font"]?.object?["size"]?.number { return size }
        return kind == "systemImage" ? 17 : nil
    }

    /// The box a button's swapped icon draws in, as web's `FLOAT_IMAGE`: fit, centred on the served icon, no layout space.
    /// The close picture's height cap in points, as web's `FLOAT_IMAGE_HEIGHT`; a capsule stays above a long title.
    static let floatImageHeight = 20.0
    static let floatImage = (width: 48.0, height: floatImageHeight)

    /// The image an icon becomes; the served icon stays as its fallback, shown while it loads and if it fails.
    /// A button's icon floats in `floatFrame` over the served icon, which keeps the layout.
    private static func iconImage(_ url: String, _ side: Double?, served: SkinObject, floats: Bool) -> SkinObject {
        let height = side ?? 17
        let fallback = served.deepCopy()
        elementOf(fallback)?.props["component"] = nil
        if floats {
            // The cap box whatever the served icon's size; the served icon still holds the layout.
            let floatFrame = SkinObject([("width", .number(floatImage.width)), ("height", .number(floatImage.height))])
            return SkinObject([("asyncImage", .object(SkinObject([
                ("url", .string(url)), ("contentMode", .string("fit")), ("floatFrame", .object(floatFrame)), ("fallback", .object(fallback)),
            ])))])
        }
        // minWidth as well as height, so a layout that sizes the image box from its frame never collapses it to zero width.
        let frame = SkinObject([("height", .number(height)), ("minWidth", .number(height)), ("maxWidth", .number(height * 2))])
        return SkinObject([("asyncImage", .object(SkinObject([
            ("url", .string(url)), ("contentMode", .string("fit")), ("style", .object(SkinObject([("frame", .object(frame))]))),
            ("fallback", .object(fallback)),
        ])))])
    }

    /// The touch area an icon button keeps once its icon becomes an image (44 pt, as both platforms advise).
    static let minTouchTarget: Double = 44

    /// Marks the button `touchTarget: 44`, as web's `keepTouchTarget`: the renderer grows its tap area, never its frame.
    private static func keepTouchTarget(_ props: SkinObject) {
        props["touchTarget"] = .number(minTouchTarget)
    }

    /// An image that covers its host's box, cropped at the edges and clipped to the host's corner.
    private static func imageLayer(_ url: String, _ cornerRadius: SkinJSON?) -> SkinObject {
        func fill() -> SkinObject { SkinObject([("maxWidth", .string("infinity")), ("maxHeight", .string("infinity"))]) }
        let image = SkinObject([("asyncImage", .object(SkinObject([
            ("url", .string(url)), ("contentMode", .string("fill")), ("style", .object(SkinObject([("frame", .object(fill()))]))),
        ])))])
        let clip = SkinObject([("rectangle", .object(SkinObject([("cornerRadius", .number(cornerRadius?.number ?? 0))])))])
        return SkinObject([("zStack", .object(SkinObject([
            ("skinLayer", .bool(true)), ("children", .array([.object(image)])),
            ("style", .object(SkinObject([("frame", .object(fill())), ("clipShape", .object(clip))]))),
        ])))])
    }

    private static func layered(_ existing: SkinJSON?, _ added: SkinJSON) -> SkinJSON {
        guard let existing else { return added }
        return .object(SkinObject([("zStack", .object(SkinObject([("skinLayer", .bool(true)), ("children", .array([existing, added]))])))]))
    }

    // MARK: Properties

    private static func applyFill(_ kind: String, _ props: SkinObject, _ color: SkinColor, _ options: Options, _ name: String) {
        if kind == "gradient" || styleless.contains(kind) {
            options.warn("skin \(name).fill does not apply to a \(kind); ignored")
            return
        }
        if kind == "shape" {
            props["fillColor"] = colorJSON(color, options.scheme)
            // Read on Android only, so a filled shape takes its space; this renderer ignores it.
            props["skinLayer"] = .bool(true)
        } else {
            styleOf(props)["backgroundColor"] = colorJSON(color, options.scheme)
        }
    }

    private static func applyCornerRadius(_ kind: String, _ props: SkinObject, _ radius: Double, _ components: [String: SkinComponentStyle]) {
        let style = styleOf(props)
        let old = style["cornerRadius"]?.number
        style["cornerRadius"] = .number(radius)
        if let rectangle = style["clipShape"]?.object?["rectangle"]?.object { rectangle["cornerRadius"] = .number(radius) }
        if kind == "shape", let type = props["type"]?.string, type == "rectangle" || type == "roundedRectangle", props["cornerRadius"] != nil {
            props["cornerRadius"] = .number(radius)
        }
        // A layer drawn to the host's old corner follows the new one, unless the skin gives that layer its own corner.
        guard let old else { return }
        for slot in ["overlay", "backgroundElement"] {
            guard let layer = style[slot] else { continue }
            eachElement(layer) { _, _, child in
                if let tag = child["component"]?.string, components[tag]?.cornerRadius != nil { return true }
                if let childStyle = child["style"]?.object, childStyle["cornerRadius"]?.number == old {
                    childStyle["cornerRadius"] = .number(radius)
                }
                return true
            }
        }
    }

    private static func applyComponent(
        _ wrapper: SkinObject, _ kind: String, _ props: SkinObject, _ entry: SkinComponentStyle, _ name: String,
        _ overlayHost: SkinObject?, _ options: Options, _ pending: inout [(host: SkinObject, name: String, color: SkinColor)],
        _ components: [String: SkinComponentStyle]
    ) {
        if let fill = entry.fill {
            // Only a shape layer moves under the content; anything else in an overlay is filled where it is.
            if let overlayHost, kind == "shape" {
                pending.append((overlayHost, name, fill))
                // The served shape stays above the content, so its own fill is cleared and the skin fill shows through.
                props["fillColor"] = .object(SkinObject([("hex", .string("#000000")), ("opacity", .number(0))]))
            } else {
                applyFill(kind, props, fill, options, name)
            }
        }
        if let radius = entry.cornerRadius {
            if styleless.contains(kind) { options.warn("skin \(name).cornerRadius does not apply to a \(kind); ignored") } else {
                applyCornerRadius(kind, props, radius, components)
            }
        }
        let borders: [(String, SkinJSON?)] = [
            ("borderWidth", entry.borderWidth.map(SkinJSON.number)),
            ("borderColor", entry.borderColor.map { colorJSON($0, options.scheme) }),
        ]
        for (key, value) in borders {
            guard let value else { continue }
            if styleless.contains(kind) { options.warn("skin \(name).\(key) does not apply to a \(kind); ignored"); continue }
            styleOf(props)[key] = value
        }
        if let contentColor = entry.contentColor {
            if kind == "compactPageIndicator" { colorDots(props, contentColor, options.scheme) } else if kind == "text" || kind == "systemImage" { colorLeaf(props, contentColor, options.scheme) } else {
                eachUntaggedLeaf(props) { _, leaf in colorLeaf(leaf, contentColor, options.scheme) }
            }
        }
        // The role marker goes on with or without an app family; a marker with none draws the system font.
        if let role = entry.font {
            if kind == "text" { setFamily(props, role) } else {
                eachUntaggedLeaf(props) { leafKind, leaf in if leafKind == "text" { setFamily(leaf, role) } }
            }
        }
        // `animation` is the image rule with its still, then the Lottie file on the image that rule drew; it wins over `image`.
        var styled = props
        // A served completion moves the sheet on, so the served animation that carries it stays, with its still.
        let keptServed = entry.animation != nil && SheetSkinReader.carriesFlow(props["animation"])
        if keptServed { options.warn("skin \(name).animation would replace a served animation with onComplete; ignored") }
        let animation = keptServed ? nil : entry.animation
        if let still = animation?.fallbackImage ?? entry.image,
           let image = applyImage(wrapper, kind, props, still, name, options, property: animation != nil ? "animation" : "image") {
            if let animation { image["animation"] = animation.variantJSON }
            // A swapped icon is a new element: its motion goes on the image that replaced it.
            if kind == "systemImage" { styled = image }
        }
        for (key, branchKey, url) in [("trueImage", "ifTrue", entry.trueImage), ("falseImage", "ifFalse", entry.falseImage)] {
            guard let url else { continue }
            guard kind == "conditional", let branch = props[branchKey]?.object else {
                options.warn("skin \(name).\(key) needs a conditional with \(branchKey); ignored")
                continue
            }
            // The served branch stays as the image's fallback, so a broken tick upload still draws the served mark.
            let image = asyncImage(url, branchSide(branch))
            image["asyncImage"]?.object?["fallback"] = .object(untagged(branch))
            props[branchKey] = .object(image)
        }
        for (key, motion) in [("enter", entry.enter), ("loop", entry.loop)] {
            guard let motion else { continue }
            if styleless.contains(kind) { options.warn("skin \(name).\(key) does not apply to a \(kind); ignored"); continue }
            // A served completion moves the sheet on, so the served motion that carries it stays.
            if SheetSkinReader.carriesFlow(styleOf(styled)[key]) {
                options.warn("skin \(name).\(key) would replace a served \(key) with onComplete; ignored")
                continue
            }
            styleOf(styled)[key] = motion.json.deepCopy()
        }
        if let backgroundImage = entry.backgroundImage {
            if styleless.contains(kind) { options.warn("skin \(name).backgroundImage does not apply to a \(kind); ignored") } else {
                // A shape has no content, so the image goes above its fill; anything else draws it behind its content.
                let style = styleOf(props)
                let slot = kind == "shape" ? "overlay" : "backgroundElement"
                // A shape keeps its corner on the element (roundedRectangle), anything else in its style.
                let radius = kind == "shape" && props["cornerRadius"]?.number != nil ? props["cornerRadius"] : style["cornerRadius"]
                style[slot] = layered(style[slot], .object(imageLayer(backgroundImage, radius)))
            }
        }
    }

    /// Returns the `asyncImage` properties it wrote the image to, or nil after a warning.
    @discardableResult
    private static func applyImage(
        _ wrapper: SkinObject, _ kind: String, _ props: SkinObject, _ url: String, _ name: String, _ options: Options, property: String
    ) -> SkinObject? {
        if kind == "asyncImage" {
            props["url"] = .string(url)
            props["urlBinding"] = nil
            return props
        }
        if kind == "systemImage" {
            let side = iconSide(kind, props)
            wrapper["systemImage"] = nil
            let replacement = iconImage(url, side, served: SkinObject([("systemImage", .object(props))]), floats: false)
            replacement["asyncImage"]?.object?["component"] = props["component"]
            wrapper["asyncImage"] = replacement["asyncImage"]
            return replacement["asyncImage"]?.object
        }
        if kind == "button", let contentObject = props["content"]?.object, let content = elementOf(contentObject) {
            var icon: String?
            if content.kind == "systemImage" { icon = content.props["systemName"]?.string }
            if content.kind == "text", let glyph = content.props["text"]?.string, glyph.unicodeScalars.count == 1 { icon = glyph }
            if let icon {
                // A glyph the SDK has no label for is still the button's name, as it was before the swap.
                let glyph = content.kind == "text" ? icon : nil
                let label = props["accessibilityLabel"]?.string != nil ? nil : options.iconLabel(icon, props["action"]?.object?["type"]?.string) ?? glyph
                let image = iconImage(url, iconSide(content.kind, content.props), served: contentObject, floats: true)
                props["content"] = .object(image)
                if let label { props["accessibilityLabel"] = .string(label) }
                keepTouchTarget(props)
                return image["asyncImage"]?.object
            }
        }
        options.warn("skin \(name).\(property) does not apply to this \(kind); ignored")
        return nil
    }

    /// `node` cut down to the path to the shapes tagged `name`: no text, image or button is drawn twice.
    private static func pruneTo(_ node: SkinJSON, _ name: String) -> SkinJSON? {
        func isContainer(_ value: SkinJSON) -> Bool {
            switch value { case .object, .array: return true; default: return false }
        }
        if case .array(let items) = node {
            let kept = items.compactMap { pruneTo($0, name) }
            return kept.isEmpty ? nil : .array(kept)
        }
        guard let object = node.object else { return nil }
        let (wholeKeys, source, wrap): (Set<String>, SkinObject, String?)
        if let (kind, props) = elementOf(object) {
            if kind == "shape", props["component"]?.string == name { return node }
            (wholeKeys, source, wrap) = (["condition", "frame"], props, kind)
        } else {
            (wholeKeys, source, wrap) = (["frame", "padding"], object, nil)
        }
        let out = SkinObject()
        var found = false
        for (key, value) in source.entries {
            if !isContainer(value) || wholeKeys.contains(key) { out[key] = value } else if let kept = pruneTo(value, name) {
                out[key] = kept
                found = true
            }
        }
        guard found else { return nil }
        return wrap.map { .object(SkinObject([($0, .object(out))])) } ?? .object(out)
    }

    private static func moveOverlayFill(_ host: SkinObject, _ name: String, _ color: SkinColor, _ scheme: SkinScheme) {
        let style = styleOf(host)
        guard let overlay = style["overlay"], let copy = pruneTo(overlay.deepCopy(), name) else { return }
        eachElement(copy) { _, kind, props in
            guard props["component"]?.string == name else { return true }
            if kind == "shape" { props["fillColor"] = colorJSON(color, scheme) } else { styleOf(props)["backgroundColor"] = colorJSON(color, scheme) }
            if let layerStyle = props["style"]?.object {
                layerStyle["borderWidth"] = nil
                layerStyle["borderColor"] = nil
            }
            props["strokeColor"] = nil
            props["strokeWidth"] = nil
            return true
        }
        // Wrapped in a zStack, so a copied root with no box of its own (a conditional) still sizes to the host.
        // `skinLayer` is read on web only, which otherwise paints this layer over the host's content.
        let wrapped = SkinJSON.object(SkinObject([("zStack", .object(SkinObject([("skinLayer", .bool(true)), ("children", .array([copy]))])))]))
        style["backgroundElement"] = layered(style["backgroundElement"], wrapped)
    }
}
