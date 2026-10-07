#if DEBUG
import SwiftUI

enum EquipmentStyle { case filled, ink }

/// Design Lab icon (supports the ink style); the production icon is `EquipmentIcon`.
struct DLEquipmentIcon: View {

    let kind: EquipmentKind
    var style: EquipmentStyle = .filled
    var intensity: Double = 0
    @Environment(\.dlTheme) private var t

    var body: some View {
        let used = intensity > 0
        let parts = kind.parts()
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 64
            let tx = CGAffineTransform(scaleX: s, y: s)
                .translatedBy(x: (size.width / s - 64) / 2, y: (size.height / s - 64) / 2)
            let main = used ? t.accent.opacity(0.5 + 0.5 * intensity) : t.dim
            let wash = t.accent.opacity(0.22 + 0.4 * intensity)
            let ink = used ? t.accent : t.dim
            let round = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
            func stroke(_ w: CGFloat) -> StrokeStyle {
                var st = round
                st.lineWidth = w * s
                return st
            }
            for part in parts {
                let p = part.path.applying(tx)
                switch (style, part.mode) {
                case (.filled, .solid):
                    if used {
                        ctx.fill(p, with: .color(main))
                    } else {
                        ctx.fill(p, with: .color(Color.white.opacity(0.04)))
                        ctx.stroke(p, with: .color(main), style: stroke(1.3))
                    }
                case (.filled, .cut(let w)):
                    if used { ctx.stroke(p, with: .color(t.card), style: stroke(w)) }
                case (.filled, .line(let w)):
                    ctx.stroke(p, with: .color(main), style: stroke(used ? w : min(w, 1.6)))
                case (.ink, .solid):
                    if used { ctx.fill(p, with: .color(wash)) }
                    ctx.stroke(p, with: .color(ink), style: stroke(1.6))
                case (.ink, .cut):
                    ctx.stroke(p, with: .color(ink.opacity(0.7)), style: stroke(0.9))
                case (.ink, .line(let w)):
                    ctx.stroke(p, with: .color(ink), style: stroke(max(1.6, w * 0.4)))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .shadow(color: (used && style == .filled) ? t.accent.opacity(0.45 * intensity) : .clear, radius: 9)
        .accessibilityLabel(kind.name)
    }
}
#endif
