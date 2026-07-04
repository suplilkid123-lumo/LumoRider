// NavigationCoordinator.swift

import SwiftUI
import Combine

final class NavigationCoordinator: ObservableObject {
    @Published var path = NavigationPath()
}
