import SwiftUI

private enum ProjectSortMode: String {
    case updated = "按更新时间排序"
    case progress = "按项目进度排序"
    case favorite = "收藏优先"
}

struct ActiveProjectsView: View {
    @ObservedObject var model: AppModel
    @State private var expandedProjectID: String?
    @State private var sortMode: ProjectSortMode = .updated

    var body: some View {
        Group {
            if !model.projectsLoaded {
                ProgressView("正在读取真实项目…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.activeProjects.isEmpty {
                ContentUnavailableView(
                    "还没有进行中的项目",
                    systemImage: "folder.badge.plus",
                    description: Text("前往“收件台”创建项目，或将已有项目目录放入当前素材库。")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        pageHeader

                        ForEach(sortedProjects) { project in
                            if project.id == expandedProjectID {
                                ExpandedProjectView(project: project, model: model)
                            } else {
                                CompactProjectRow(project: project, model: model) {
                                    withAnimation(.snappy(duration: 0.34)) {
                                        expandedProjectID = project.id
                                    }
                                }
                            }
                        }

                        Text("\(sortedProjects.count) 个项目")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 24)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("进行中")
        .onChange(of: model.activeProjects.map(\.id), initial: true) { _, projectIDs in
            if expandedProjectID == nil || !projectIDs.contains(expandedProjectID ?? "") {
                expandedProjectID = projectIDs.first
            }
        }
    }

    private var sortedProjects: [CreatorProject] {
        switch sortMode {
        case .updated:
            model.activeProjects.sorted { $0.updatedEpoch > $1.updatedEpoch }
        case .progress:
            model.activeProjects.sorted { $0.progress > $1.progress }
        case .favorite:
            model.activeProjects.sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
                return $0.updatedEpoch > $1.updatedEpoch
            }
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("进行中")
                    .font(.system(size: 30, weight: .bold))
                Text("这里显示素材库中的真实项目，阶段变化会自动保存。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                ForEach([ProjectSortMode.updated, .progress, .favorite], id: \.rawValue) { mode in
                    Button(mode.rawValue) { sortMode = mode }
                }
            } label: {
                Label(sortMode.rawValue, systemImage: "arrow.up.arrow.down")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .menuStyle(.borderlessButton)
            .creatorGlass(cornerRadius: 15, interactive: true)

            Text(Self.todayText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .creatorGlass(cornerRadius: 15)
        }
    }

    private static var todayText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "今天 yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

struct CompletedProjectsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if !model.projectsLoaded {
                ProgressView("正在读取真实项目…")
            } else if model.completedProjects.isEmpty {
                ContentUnavailableView(
                    "还没有 Done 项目",
                    systemImage: "checkmark.circle",
                    description: Text("完成全部必需阶段后，项目会保留在这里。")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("已完成")
                            .font(.system(size: 30, weight: .bold))
                        Text("已归档的项目仍可打开或重新进入制作流程。")
                            .foregroundStyle(.secondary)

                        ForEach(model.completedProjects.sorted(by: { $0.updatedEpoch > $1.updatedEpoch })) { project in
                            HStack(spacing: 16) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(project.name).font(.headline)
                                    Text(project.updatedText).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("Done")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                                Button("打开") { model.openProject(project) }
                                    .buttonStyle(GlassActionButtonStyle())
                                Button("重新打开") {
                                    Task { await model.setProjectStage(project, stageID: "archive") }
                                }
                                .buttonStyle(GlassActionButtonStyle())
                            }
                            .padding(18)
                            .background(.background, in: RoundedRectangle(cornerRadius: 14))
                            .overlay { RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.45)) }
                        }
                    }
                    .padding(30)
                }
            }
        }
        .navigationTitle("已完成")
    }
}

struct DevicesView: View {
    @ObservedObject var model: AppModel

    private var devices: [(name: String, symbol: String, projectCount: Int)] {
        let allDevices = model.projects.flatMap(\.devices)
        let names = Set(allDevices.map(\.name))
        return names.sorted().map { name in
            let matches = allDevices.filter { $0.name == name }
            return (name, matches.first?.symbol ?? "camera", matches.count)
        }
    }

    var body: some View {
        Group {
            if devices.isEmpty {
                ContentUnavailableView(
                    "尚未识别到设备目录",
                    systemImage: "externaldrive.connected.to.line.below",
                    description: Text("素材导入后会按日期和设备整理到项目的 01_MEDIA 中。")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                        ForEach(devices, id: \.name) { device in
                            HStack(spacing: 14) {
                                Image(systemName: device.symbol)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(Color.accentColor.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name).font(.headline)
                                    Text("出现在 \(device.projectCount) 个项目中")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(16)
                            .background(.background, in: RoundedRectangle(cornerRadius: 14))
                            .overlay { RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.45)) }
                        }
                    }
                    .padding(30)
                }
            }
        }
        .navigationTitle("设备")
    }
}

private struct ExpandedProjectView: View {
    let project: CreatorProject
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.top, 16)
            ProjectStageRail(project: project)
                .padding(.vertical, 25)
            sourceAndDestination
            Divider().padding(.top, 18)
            footer
        }
        .padding(24)
        .background(.background, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.separator.opacity(0.5), lineWidth: 0.8)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    Text(project.name)
                        .font(.system(size: 23, weight: .semibold))
                    Button {
                        Task { await model.setProjectFavorite(project, favorite: !project.isFavorite) }
                    } label: {
                        Image(systemName: project.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(project.isFavorite ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(project.isFavorite ? "取消收藏" : "收藏项目")
                }
                Text(project.updatedText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("\(project.progress)%")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(project.progress >= 90 ? .green : Color.accentColor)
                Text("整体进度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 86, height: 68)
            .creatorGlass(cornerRadius: 18)

            Button("继续项目") { model.openProject(project) }
                .buttonStyle(GlassActionButtonStyle(isProminent: true))

            projectMenu
        }
    }

    private var projectMenu: some View {
        Menu {
            Button("在 Finder 中显示") { model.openProject(project) }
            Button(project.isFavorite ? "取消收藏" : "收藏项目") {
                Task { await model.setProjectFavorite(project, favorite: !project.isFavorite) }
            }
            Divider()
            Menu("设置项目阶段") {
                ForEach(CreatorProject.stages) { stage in
                    Button(stage.name) {
                        Task { await model.setProjectStage(project, stageID: stage.id) }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
        }
        .menuStyle(.borderlessButton)
        .creatorGlass(cornerRadius: 19, interactive: true)
    }

    private var sourceAndDestination: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("来源设备").font(.headline)
                HStack(spacing: 10) {
                    if project.devices.isEmpty {
                        DeviceTile(device: CreatorDevice(
                            id: "unidentified-\(project.id)", name: "未识别", detail: "等待素材目录", symbol: "questionmark"
                        ))
                    } else {
                        ForEach(project.devices.prefix(4)) { device in
                            DeviceTile(device: device)
                        }
                    }
                }
            }

            Image(systemName: "arrow.right")
                .font(.title2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 48)

            VStack(alignment: .leading, spacing: 12) {
                Text("主素材库").font(.headline)
                HStack(spacing: 15) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 31))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(project.destinationName).font(.headline)
                        Label(project.storageSummary, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary, .orange)
                        Text(project.destinationPath)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 18)
                .frame(height: 104)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
                .overlay { RoundedRectangle(cornerRadius: 13).stroke(.separator.opacity(0.45)) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Label(project.completedStageSummary,
                  systemImage: project.currentStageIndex == 0 ? "clock" : "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(
                    Color.secondary,
                    project.currentStageIndex == 0 ? Color.secondary : Color.green
                )
            Spacer()
            Button(project.nextStageID == "done" ? "完成并归档" : "标记当前阶段完成") {
                Task { await model.advanceProject(project) }
            }
            .buttonStyle(GlassActionButtonStyle())
            .disabled(model.isWorking || project.isComplete)
        }
        .padding(.top, 14)
    }
}

private struct ProjectStageRail: View {
    let project: CreatorProject

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(CreatorProject.stages.enumerated()), id: \.element.id) { index, stage in
                VStack(spacing: 8) {
                    ZStack {
                        if index > 0 {
                            Rectangle()
                                .fill(lineColor(for: index - 1))
                                .frame(height: 2)
                                .frame(maxWidth: .infinity)
                                .offset(x: -35)
                        }
                        Circle()
                            .fill(circleColor(for: index))
                            .frame(width: 34, height: 34)
                        Image(systemName: symbol(for: index, fallback: stage.symbol))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(iconColor(for: index))
                    }
                    Text(stage.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(statusText(for: index))
                        .font(.system(size: 12))
                        .foregroundStyle(project.state(for: index) == .current ? Color.accentColor : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func symbol(for index: Int, fallback: String) -> String {
        project.state(for: index) == .completed ? "checkmark" : fallback
    }

    private func statusText(for index: Int) -> String {
        switch project.state(for: index) {
        case .completed: "已完成"
        case .current: index == CreatorProject.stages.count - 1 ? "完成" : "进行中"
        case .pending: "待开始"
        }
    }

    private func circleColor(for index: Int) -> Color {
        switch project.state(for: index) {
        case .completed: .green
        case .current: .accentColor
        case .pending: Color(nsColor: .controlBackgroundColor)
        }
    }

    private func lineColor(for index: Int) -> Color {
        project.state(for: index) == .completed ? .green : Color(nsColor: .separatorColor)
    }

    private func iconColor(for index: Int) -> Color {
        project.state(for: index) == .pending ? .secondary : .white
    }
}

private struct DeviceTile: View {
    let device: CreatorDevice

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: device.symbol)
                .font(.system(size: 27))
                .symbolRenderingMode(.hierarchical)
                .frame(height: 34)
            Text(device.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(device.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 118, height: 104)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(.separator.opacity(0.45)) }
    }
}

private struct CompactProjectRow: View {
    let project: CreatorProject
    @ObservedObject var model: AppModel
    let expand: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(project.name).font(.system(size: 17, weight: .semibold))
                    if project.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                }
                Text(project.updatedText).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            ProgressView(value: Double(project.progress), total: 100)
                .tint(project.progress >= 90 ? .green : .accentColor)
                .frame(width: 210)
            Text("\(project.progress)%")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(project.progress >= 90 ? .green : Color.accentColor)
                .frame(width: 62, alignment: .trailing)
            Menu {
                Button("打开项目") { model.openProject(project) }
                Button("标记为 Done") {
                    Task { await model.setProjectStage(project, stageID: "done") }
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
            .creatorGlass(cornerRadius: 15, interactive: true)
            Button(action: expand) {
                Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("展开 \(project.name)")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 0.8)
        }
    }
}
