// BrineView.swift — where idle tabs sink. Plain rows (manifest §8 "Ask the Pantry" rules:
// rows, jar provenance, no chat bubbles). Restore reopens a tab with scroll and history.

import Pantry
import SwiftUI

struct BrineView: View {
    @Bindable var workbench: Workbench

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: NRSpace.sp3) {
                NRSymbol.sink.image.resizable().frame(width: 20, height: 20).foregroundStyle(NRColor.fg2)
                Text("Brine").font(NRType.font(NRType.fsLg, weight: .semibold)).foregroundStyle(NRColor.fg)
                NRBadge("\(workbench.brine.count) sunk")
                Spacer()
                Text("Tabs sink here when their jar's shelf life runs out. Nothing is lost.")
                    .font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg3)
            }
            .padding(NRSpace.sp4)
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            if workbench.brine.isEmpty {
                EmptyBench(message: "Nothing has sunk yet.")
            } else {
                List(workbench.brine) { item in
                    HStack(spacing: NRSpace.sp3) {
                        Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(NRColor.fg3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(NRType.font(NRType.fsMd)).foregroundStyle(NRColor.fg).lineLimit(1)
                            Text("\(item.domain ?? "") · sank \(item.updatedAt.formatted(.relative(presentation: .named)))")
                                .font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2)
                        }
                        Spacer()
                        if let origin = item.sunkOriginJarId, let jar = workbench.jars.first(where: { $0.id == origin }) {
                            HStack(spacing: NRSpace.sp1) {
                                NRSymbol.jar.image.resizable().frame(width: 12, height: 12)
                                Text(jar.name).font(NRType.font(NRType.fsXs))
                            }
                            .foregroundStyle(NRColor.fg2)
                            .padding(.horizontal, NRSpace.sp2).padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: NRRadius.r1).strokeBorder(NRColor.hairline, lineWidth: NRSpace.hairline))
                        }
                        Button("Restore") { workbench.restore(item) }.buttonStyle(.nrSecondary)
                    }
                    .padding(.vertical, NRSpace.sp1)
                    .listRowSeparatorTint(NRColor.hairline)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(NRColor.surface)
    }
}
