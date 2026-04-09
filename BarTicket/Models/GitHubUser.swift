import Foundation

struct GitHubUser: Codable {
    let login: String
    let name: String?
    let avatarUrl: String
    let email: String?
    let htmlUrl: String
    let publicRepos: Int

    enum CodingKeys: String, CodingKey {
        case login, name, email
        case avatarUrl = "avatar_url"
        case htmlUrl = "html_url"
        case publicRepos = "public_repos"
    }
}
