import XCTest
@testable import itstime

final class UpdateManagerTests: XCTestCase {
    
    func testSemVerComparison() {
        // 基本递增
        XCTAssertTrue(SemVer("1.0.1") > SemVer("1.0.0"))
        XCTAssertTrue(SemVer("1.1.0") > SemVer("1.0.9"))
        XCTAssertTrue(SemVer("2.0.0") > SemVer("1.9.9"))
        
        // 包含 "v" 前缀
        XCTAssertTrue(SemVer("v1.0.1") > SemVer("v1.0.0"))
        XCTAssertTrue(SemVer("V1.2.0") > SemVer("v1.1.9"))
        XCTAssertTrue(SemVer("v1.0.1") > SemVer("1.0.0"))
        
        // 相等情况
        XCTAssertEqual(SemVer("1.0.0"), SemVer("v1.0.0"))
        XCTAssertEqual(SemVer("1.0"), SemVer("1.0.0"))
        XCTAssertFalse(SemVer("1.0.0") > SemVer("1.0.0"))
        XCTAssertFalse(SemVer("1.0.0") < SemVer("1.0.0"))
        
        // 旧版本不大于新版本
        XCTAssertFalse(SemVer("1.0.0") > SemVer("1.0.1"))
        XCTAssertFalse(SemVer("1.0.0") > SemVer("2.0.0"))
    }
    
    func testGitHubReleaseJsonDecoding() throws {
        let json = """
        {
            "tag_name": "v1.1.0",
            "name": "It's Time 1.1.0 发布",
            "body": "1. 新增就地更新功能\\n2. 性能提升与界面优化",
            "html_url": "https://github.com/simpfly/its-time-mac/releases/tag/v1.1.0",
            "published_at": "2026-11-24T12:00:00Z",
            "assets": [
                {
                    "name": "ItsTime-update.zip",
                    "browser_download_url": "https://github.com/simpfly/its-time-mac/releases/download/v1.1.0/ItsTime-update.zip",
                    "size": 5242880,
                    "content_type": "application/zip"
                }
            ]
        }
        """
        
        let data = json.data(using: .utf8)!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        
        XCTAssertEqual(release.tagName, "v1.1.0")
        XCTAssertEqual(release.name, "It's Time 1.1.0 发布")
        XCTAssertEqual(release.assets.count, 1)
        XCTAssertEqual(release.assets[0].name, "ItsTime-update.zip")
        XCTAssertEqual(release.assets[0].size, 5242880)
        XCTAssertEqual(release.assets[0].browserDownloadURL, "https://github.com/simpfly/its-time-mac/releases/download/v1.1.0/ItsTime-update.zip")
    }
    
    func testUpdateStateEquality() {
        XCTAssertEqual(UpdateManager.UpdateState.idle, UpdateManager.UpdateState.idle)
        XCTAssertEqual(UpdateManager.UpdateState.checking, UpdateManager.UpdateState.checking)
        XCTAssertEqual(UpdateManager.UpdateState.upToDate, UpdateManager.UpdateState.upToDate)
        XCTAssertEqual(UpdateManager.UpdateState.downloading(progress: 0.5), UpdateManager.UpdateState.downloading(progress: 0.5))
        XCTAssertNotEqual(UpdateManager.UpdateState.downloading(progress: 0.5), UpdateManager.UpdateState.downloading(progress: 0.8))
        XCTAssertEqual(UpdateManager.UpdateState.error("超时"), UpdateManager.UpdateState.error("超时"))
    }
}
