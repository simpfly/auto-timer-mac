import SwiftUI

struct AboutView: View {
    private let projectURL = URL(string: "https://github.com/simpfly/its-time-mac")!
    private let blogURL = URL(string: "https://www.simpfly.info/")!
    @State private var starCount: Int?
    @State private var isStarHovered = false
    private static let githubIcon: NSImage = {
        guard let url = Bundle.module.url(forResource: "GitHubMark", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return NSImage() }
        return image
    }()

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(nsImage: BrandIcon.menuBar)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("It's Time")
                        .font(.system(size: 26, weight: .semibold))
                    Text("版本 \(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Text("由")
                    Link("simpfly", destination: blogURL)
                        .buttonStyle(.link)
                    Text("开发")
                }
                .font(.subheadline)
            }

            Link(destination: projectURL) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Color.accentColor
                        .mask {
                            Image(nsImage: Self.githubIcon)
                                .resizable()
                                .scaledToFit()
                                .colorInvert()
                                .luminanceToAlpha()
                        }
                        .frame(width: 20, height: 20)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                        .accessibilityHidden(true)
                    Text("GitHub")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: isStarHovered ? "star.fill" : "star")
                        Text(starCount.map { String($0) } ?? "—")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(isStarHovered ? Color.orange : Color.secondary)
                    .contentShape(Rectangle())
                    .onHover { isStarHovered = $0 }
                    .onDisappear { isStarHovered = false }
                    .accessibilityLabel(starCount.map { "\($0) 个 Star" } ?? "星标数暂不可用")
                }
                .font(.subheadline)
                .fixedSize()
            }
            .buttonStyle(.link)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(32)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadStarCount()
        }
    }

    private func loadStarCount() async {
        struct Repository: Decodable {
            let stargazers_count: Int
        }

        let url = URL(string: "https://api.github.com/repos/simpfly/its-time-mac")!
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { return }
            let repository = try JSONDecoder().decode(Repository.self, from: data)
            starCount = repository.stargazers_count
        } catch {
            // Keep the project link usable when offline or rate-limited.
        }
    }
}
