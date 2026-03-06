//
//  SDUIStyleModifiers.swift
//  Encore
//
//  Style modifiers for Server-Driven UI elements
//

import SwiftUI

// MARK: - Style Modifier (broken into sub-modifiers for compiler performance)

@available(iOS 17.0, *)
struct SDUIStyleModifier: ViewModifier {
    let style: SDUIStyle?
    
    func body(content: Content) -> some View {
        content
            .modifier(SDUIContainerRelativeFrameModifier(config: style?.containerRelativeFrame))
            .modifier(SDUIPaddingModifier(padding: style?.padding))
            .modifier(SDUIFrameModifier(frame: style?.frame))
            .modifier(SDUIClippedModifier(clipped: style?.clipped))
            .modifier(SDUIBackgroundModifier(color: style?.backgroundColor))
            .modifier(SDUICornerRadiiModifier(cornerRadii: style?.cornerRadii))
            .modifier(SDUICornerRadiusModifier(radius: style?.cornerRadii == nil ? style?.cornerRadius : nil))
            .modifier(SDUIBorderModifier(width: style?.borderWidth, color: style?.borderColor, cornerRadius: style?.cornerRadius))
            .modifier(SDUIShadowModifier(shadow: style?.shadow))
            .modifier(SDUIOpacityModifier(opacity: style?.opacity))
            .modifier(SDUIClipShapeModifier(clipShape: style?.clipShape))
            .modifier(SDUISafeAreaModifier(ignoresSafeArea: style?.ignoresSafeArea))
            .modifier(SDUILayoutPriorityModifier(priority: style?.layoutPriority))
    }
}

@available(iOS 17.0, *)
struct SDUIPaddingModifier: ViewModifier {
    let padding: SDUIPadding?
    func body(content: Content) -> some View {
        content.padding(padding?.edgeInsets ?? EdgeInsets())
    }
}

@available(iOS 17.0, *)
struct SDUIFrameModifier: ViewModifier {
    let frame: SDUIFrame?
    func body(content: Content) -> some View {
        content
            .frame(width: frame?.width, height: frame?.height)
            .frame(
                minWidth: frame?.minWidth,
                maxWidth: frame?.maxWidthValue,
                minHeight: frame?.minHeight,
                maxHeight: frame?.maxHeightValue,
                alignment: frame?.alignment?.alignment ?? .center
            )
    }
}

@available(iOS 17.0, *)
struct SDUIClippedModifier: ViewModifier {
    let clipped: Bool?
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if clipped == true {
            content.clipped()
        } else {
            content
        }
    }
}

@available(iOS 17.0, *)
struct SDUIBackgroundModifier: ViewModifier {
    let color: SDUIColor?
    func body(content: Content) -> some View {
        content.background(color?.color ?? Color.clear)
    }
}

@available(iOS 17.0, *)
struct SDUICornerRadiusModifier: ViewModifier {
    let radius: CGFloat?
    func body(content: Content) -> some View {
        content.cornerRadius(radius ?? 0)
    }
}

@available(iOS 17.0, *)
struct SDUICornerRadiiModifier: ViewModifier {
    let cornerRadii: SDUICornerRadii?
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if let cornerRadii = cornerRadii {
            content.clipShape(
                UnevenRoundedRectangle(cornerRadii: cornerRadii.rectCornerRadii)
            )
        } else {
            content
        }
    }
}

@available(iOS 17.0, *)
struct SDUIBorderModifier: ViewModifier {
    let width: CGFloat?
    let color: SDUIColor?
    let cornerRadius: CGFloat?
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if let width = width, let color = color {
            content.overlay(
                RoundedRectangle(cornerRadius: cornerRadius ?? 0)
                    .strokeBorder(color.color, lineWidth: width)
            )
        } else {
            content
        }
    }
}

@available(iOS 17.0, *)
struct SDUIShadowModifier: ViewModifier {
    let shadow: SDUIShadow?
    func body(content: Content) -> some View {
        content.shadow(
            color: shadow?.color.color.opacity(shadow?.opacity ?? 0.1) ?? Color.clear,
            radius: shadow?.radius ?? 0,
            x: shadow?.x ?? 0,
            y: shadow?.y ?? 0
        )
    }
}

@available(iOS 17.0, *)
struct SDUIOpacityModifier: ViewModifier {
    let opacity: CGFloat?
    func body(content: Content) -> some View {
        content.opacity(opacity ?? 1.0)
    }
}

@available(iOS 17.0, *)
struct SDUIClipShapeModifier: ViewModifier {
    let clipShape: SDUIClipShape?
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if let clipShape = clipShape {
            switch clipShape {
            case .rectangle(let cornerRadius):
                content.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            case .circle:
                content.clipShape(Circle())
            case .capsule:
                content.clipShape(Capsule())
            }
        } else {
            content
        }
    }
}

@available(iOS 17.0, *)
struct SDUISafeAreaModifier: ViewModifier {
    let ignoresSafeArea: Bool?
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if ignoresSafeArea == true {
            content.ignoresSafeArea()
        } else {
            content
        }
    }
}

@available(iOS 17.0, *)
struct SDUILayoutPriorityModifier: ViewModifier {
    let priority: Double?
    func body(content: Content) -> some View {
        content.layoutPriority(priority ?? 0)
    }
}

@available(iOS 17.0, *)
struct SDUIContainerRelativeFrameModifier: ViewModifier {
    let config: SDUIContainerRelativeFrame?
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if let config = config {
            switch config.axis ?? .horizontal {
            case .horizontal:
                content.containerRelativeFrame(.horizontal)
            case .vertical:
                content.containerRelativeFrame(.vertical)
            }
        } else {
            content
        }
    }
}

// MARK: - ScrollView Extensions

@available(iOS 17.0, *)
extension View {
    @ViewBuilder
    func applyScrollTargetBehavior(_ behavior: SDUIScrollTargetBehavior?) -> some View {
        if let behavior = behavior {
            switch behavior {
            case .viewAligned:
                self.scrollTargetBehavior(.viewAligned)
            case .paging:
                self.scrollTargetBehavior(.paging)
            }
        } else {
            self
        }
    }
    
    @ViewBuilder
    func applyContentMargins(_ margins: SDUIPadding?, axis: Axis.Set) -> some View {
        if let margins = margins {
            if axis == .horizontal {
                self.contentMargins(.horizontal, margins.edgeInsets.leading, for: .scrollContent)
            } else {
                self.contentMargins(.vertical, margins.edgeInsets.top, for: .scrollContent)
            }
        } else {
            self
        }
    }
}
