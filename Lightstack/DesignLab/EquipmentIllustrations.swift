#if DEBUG
import SwiftUI

enum EquipmentKind: CaseIterable, Identifiable {
    case barbell, dumbbells, kettlebell, cable, machine, bench, bodyweight
    var id: Self { self }

    var name: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbells: "Dumbbells"
        case .kettlebell: "Kettlebell"
        case .cable: "Cable"
        case .machine: "Machine"
        case .bench: "Bench"
        case .bodyweight: "Bodyweight"
        }
    }
}

enum EquipmentStyle { case filled, ink }

/// One drawable piece of an illustration, in a 64x64 coordinate space.
struct EquipPart {
    enum Mode { case solid, cut(CGFloat), line(CGFloat) }
    let path: Path
    let mode: Mode
}

private func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 1.5) -> Path {
    Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
}
private func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
}
private func seg(_ pts: [(CGFloat, CGFloat)]) -> Path {
    var p = Path()
    guard let first = pts.first else { return p }
    p.move(to: CGPoint(x: first.0, y: first.1))
    for pt in pts.dropFirst() { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
    return p
}

extension EquipmentKind {
    func parts() -> [EquipPart] {
        switch self {
        case .barbell:
            return [
                EquipPart(path: rr(2, 30, 60, 4, 2), mode: .solid),
                EquipPart(path: rr(11, 12, 7, 40, 3), mode: .solid),
                EquipPart(path: rr(19.5, 19, 5, 26, 2.5), mode: .solid),
                EquipPart(path: rr(46, 12, 7, 40, 3), mode: .solid),
                EquipPart(path: rr(39.5, 19, 5, 26, 2.5), mode: .solid),
                EquipPart(path: seg([(14.5, 18), (14.5, 46)]), mode: .cut(1))
            ]
        case .dumbbells:
            func db(_ y: CGFloat, _ dx: CGFloat) -> [EquipPart] {
                [
                    EquipPart(path: rr(21 + dx, y - 1.8, 22, 3.6, 1.8), mode: .solid),
                    EquipPart(path: rr(10 + dx, y - 8, 11, 16, 3.5), mode: .solid),
                    EquipPart(path: rr(43 + dx, y - 8, 11, 16, 3.5), mode: .solid),
                    EquipPart(path: seg([(14 + dx, y - 4), (14 + dx, y + 4)]), mode: .cut(1))
                ]
            }
            return db(18, -3) + db(42, 3)
        case .kettlebell:
            return [
                EquipPart(path: seg([(23, 27), (23, 17), (27, 12), (37, 12), (41, 17), (41, 27)]), mode: .line(4.5)),
                EquipPart(path: circle(32, 39, 16), mode: .solid),
                EquipPart(path: rr(21, 51, 22, 5, 2.5), mode: .solid),
                EquipPart(path: Path { p in
                    p.addArc(center: CGPoint(x: 32, y: 39), radius: 10, startAngle: .degrees(150),
                             endAngle: .degrees(200), clockwise: false)
                }, mode: .cut(1.6))
            ]
        case .cable:
            var parts: [EquipPart] = [
                EquipPart(path: rr(4, 56, 44, 4, 2), mode: .solid),
                EquipPart(path: rr(6, 4, 4, 54, 1.5), mode: .solid),
                EquipPart(path: rr(40, 4, 4, 54, 1.5), mode: .solid),
                EquipPart(path: rr(6, 4, 38, 4, 1.5), mode: .solid)
            ]
            for i in 0..<6 {
                parts.append(EquipPart(path: rr(13, 17 + CGFloat(i) * 6.3, 24, 4.6, 1.2), mode: .solid))
            }
            parts.append(EquipPart(path: seg([(25, 17), (25, 12), (52, 12)]), mode: .line(1.6)))
            parts.append(EquipPart(path: circle(52, 12, 4.5), mode: .solid))
            parts.append(EquipPart(path: circle(52, 12, 1.4), mode: .cut(1.4)))
            parts.append(EquipPart(path: seg([(52, 16.5), (52, 42)]), mode: .line(1.6)))
            parts.append(EquipPart(path: circle(52, 46, 4), mode: .line(2.2)))
            return parts
        case .machine:
            var parts: [EquipPart] = [
                EquipPart(path: rr(4, 56, 56, 4, 2), mode: .solid),
                EquipPart(path: seg([(10, 18), (17, 16), (23, 39), (16, 41)]).closedSubpath(), mode: .solid),
                EquipPart(path: rr(14, 42, 22, 6, 3), mode: .solid),
                EquipPart(path: rr(23, 48, 5, 8, 1), mode: .solid),
                EquipPart(path: rr(38, 10, 5, 46, 2), mode: .solid),
                EquipPart(path: seg([(40, 24), (30, 30)]), mode: .line(3.6)),
                EquipPart(path: circle(29, 31, 3.6), mode: .solid)
            ]
            for i in 0..<5 {
                parts.append(EquipPart(path: rr(47, 24 + CGFloat(i) * 6.4, 13, 4.8, 1.2), mode: .solid))
            }
            parts.append(EquipPart(path: seg([(53.5, 24), (53.5, 12), (43, 12)]), mode: .line(1.4)))
            return parts
        case .bench:
            return [
                EquipPart(path: rr(4, 22, 56, 10, 4.5), mode: .solid),
                EquipPart(path: seg([(14, 32), (12, 52)]), mode: .line(4)),
                EquipPart(path: seg([(50, 32), (52, 52)]), mode: .line(4)),
                EquipPart(path: rr(5, 52, 16, 4, 2), mode: .solid),
                EquipPart(path: rr(43, 52, 16, 4, 2), mode: .solid),
                EquipPart(path: seg([(13, 42), (51, 42)]), mode: .line(2.6)),
                EquipPart(path: seg([(11, 27), (53, 27)]), mode: .cut(1))
            ]
        case .bodyweight:
            return [
                EquipPart(path: circle(32, 11, 6.5), mode: .solid),
                EquipPart(path: seg([(32, 21), (32, 38)]), mode: .line(8)),
                EquipPart(path: seg([(32, 23), (17, 13)]), mode: .line(5)),
                EquipPart(path: seg([(32, 23), (47, 13)]), mode: .line(5)),
                EquipPart(path: seg([(32, 38), (21, 56)]), mode: .line(5.5)),
                EquipPart(path: seg([(32, 38), (43, 56)]), mode: .line(5.5))
            ]
        }
    }
}

private extension Path {
    func closedSubpath() -> Path {
        var p = self
        p.closeSubpath()
        return p
    }
}

/// intensity: 0 = unused (dim outline), 0.2...1 = glow strength by set count.
struct EquipmentIcon: View {
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
