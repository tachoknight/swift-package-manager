/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

public class Target: ObjectIdentifierProtocol {
    /// The target kind.
    public enum Kind: String {
        case executable
        case library
        case systemModule = "system-target"
        case test
        case binary
    }

    /// A reference to a product from a target dependency.
    public struct ProductReference {

        /// The name of the product dependency.
        public let name: String

        /// The name of the package containing the product.
        public let package: String?

        /// Creates a product reference instance.
        public init(name: String, package: String?) {
            self.name = name
            self.package = package
        }
    }

    /// A target dependency to a target or product.
    public enum Dependency {

        /// A dependency referencing another target, with conditions.
        case target(_ target: Target, conditions: [PackageConditionProtocol])

        /// A dependency referencing a product, with conditions.
        case product(_ product: ProductReference, conditions: [PackageConditionProtocol])

        /// The target if the dependency is a target dependency.
        public var target: Target? {
            if case .target(let target, _) = self {
                return target
            } else {
                return nil
            }
        }

        /// The product reference if the dependency is a product dependency.
        public var product: ProductReference? {
            if case .product(let product, _) = self {
                return product
            } else {
                return nil
            }
        }

        /// The dependency conditions.
        public var conditions: [PackageConditionProtocol] {
            switch self {
            case .target(_, let conditions):
                return conditions
            case .product(_, let conditions):
                return conditions
            }
        }

        /// The name of the target or product of the dependency.
        public var name: String {
            switch self {
            case .target(let target, _):
                return target.name
            case .product(let product, _):
                return product.name
            }
        }
    }

    /// The name of the target.
    ///
    /// NOTE: This name is not the language-level target (i.e., the importable
    /// name) name in many cases, instead use c99name if you need uniqueness.
    public let name: String

    /// The default localization for resources.
    public let defaultLocalization: String?

    /// The dependencies of this target.
    public let dependencies: [Dependency]

    /// The language-level target name.
    public let c99name: String

    /// The bundle name, if one is being generated.
    public let bundleName: String?

    /// Suffix that's expected for test targets.
    public static let testModuleNameSuffix = "Tests"

    /// The kind of target.
    public let type: Kind

    /// The sources for the target.
    public let sources: Sources

    /// The resource files in the target.
    public let resources: [Resource]

    /// The list of platforms that are supported by this target.
    public let platforms: [SupportedPlatform]

    /// Returns the supported platform instance for the given platform.
    public func getSupportedPlatform(for platform: Platform) -> SupportedPlatform? {
        return self.platforms.first(where: { $0.platform == platform })
    }

    /// The build settings assignments of this target.
    public let buildSettings: BuildSettings.AssignmentTable

    fileprivate init(
        name: String,
        bundleName: String? = nil,
        defaultLocalization: String?,
        platforms: [SupportedPlatform],
        type: Kind,
        sources: Sources,
        resources: [Resource] = [],
        dependencies: [Target.Dependency],
        buildSettings: BuildSettings.AssignmentTable
    ) {
        self.name = name
        self.bundleName = bundleName
        self.defaultLocalization = defaultLocalization
        self.platforms = platforms
        self.type = type
        self.sources = sources
        self.resources = resources
        self.dependencies = dependencies
        self.c99name = self.name.spm_mangledToC99ExtendedIdentifier()
        self.buildSettings = buildSettings
    }
}

public class SwiftTarget: Target {

    /// The file name of linux main file.
    public static let linuxMainBasename = "LinuxMain.swift"

    public init(testDiscoverySrc: Sources, name: String, dependencies: [Target.Dependency]) {
        self.swiftVersion = .v5

        super.init(
            name: name,
            defaultLocalization: nil,
            platforms: [],
            type: .executable,
            sources: testDiscoverySrc,
            dependencies: dependencies,
            buildSettings: .init()
        )
    }

    /// Create an executable Swift target from linux main test manifest file.
    init(linuxMain: AbsolutePath, name: String, dependencies: [Target.Dependency]) {
        // Look for the first swift test target and use the same swift version
        // for linux main target. This will need to change if we move to a model
        // where we allow per target swift language version build settings.
        let swiftTestTarget = dependencies.first {
            guard case .target(let target as SwiftTarget, _) = $0 else { return false }
            return target.type == .test
        }.flatMap { $0.target as? SwiftTarget }

        // FIXME: This is not very correct but doesn't matter much in practice.
        // We need to select the latest Swift language version that can
        // satisfy the current tools version but there is not a good way to
        // do that currently.
        self.swiftVersion = swiftTestTarget?.swiftVersion ?? SwiftLanguageVersion(string: String(ToolsVersion.currentToolsVersion.major)) ?? .v4
        let sources = Sources(paths: [linuxMain], root: linuxMain.parentDirectory)

        let platforms: [SupportedPlatform] = swiftTestTarget?.platforms ?? []

        super.init(
            name: name,
            defaultLocalization: nil,
            platforms: platforms,
            type: .executable,
            sources: sources,
            dependencies: dependencies,
            buildSettings: .init()
        )
    }

    /// The swift version of this target.
    public let swiftVersion: SwiftLanguageVersion

    public init(
        name: String,
        bundleName: String? = nil,
        defaultLocalization: String? = nil,
        platforms: [SupportedPlatform] = [],
        isTest: Bool = false,
        sources: Sources,
        resources: [Resource] = [],
        dependencies: [Target.Dependency] = [],
        swiftVersion: SwiftLanguageVersion,
        buildSettings: BuildSettings.AssignmentTable = .init()
    ) {
        let type: Kind = isTest ? .test : sources.computeTargetType()
        self.swiftVersion = swiftVersion
        super.init(
            name: name,
            bundleName: bundleName,
            defaultLocalization: defaultLocalization,
            platforms: platforms,
            type: type,
            sources: sources,
            resources: resources,
            dependencies: dependencies,
            buildSettings: buildSettings
        )
    }
}

public class SystemLibraryTarget: Target {

    /// The name of pkgConfig file, if any.
    public let pkgConfig: String?

    /// List of system package providers, if any.
    public let providers: [SystemPackageProviderDescription]?

    /// The package path.
    public var path: AbsolutePath {
        return sources.root
    }

    /// True if this system library should become implicit target
    /// dependency of its dependent packages.
    public let isImplicit: Bool

    public init(
        name: String,
        platforms: [SupportedPlatform] = [],
        path: AbsolutePath,
        isImplicit: Bool = true,
        pkgConfig: String? = nil,
        providers: [SystemPackageProviderDescription]? = nil
    ) {
        let sources = Sources(paths: [], root: path)
        self.pkgConfig = pkgConfig
        self.providers = providers
        self.isImplicit = isImplicit
        super.init(
            name: name,
            defaultLocalization: nil,
            platforms: platforms,
            type: .systemModule,
            sources: sources,
            dependencies: [],
            buildSettings: .init()
        )
    }
}

public class ClangTarget: Target {

    /// The default public include directory component.
    public static let defaultPublicHeadersComponent = "include"

    /// The path to include directory.
    public let includeDir: AbsolutePath

    /// True if this is a C++ target.
    public let isCXX: Bool

    /// The C language standard flag.
    public let cLanguageStandard: String?

    /// The C++ language standard flag.
    public let cxxLanguageStandard: String?

    public init(
        name: String,
        bundleName: String? = nil,
        defaultLocalization: String? = nil,
        platforms: [SupportedPlatform] = [],
        cLanguageStandard: String?,
        cxxLanguageStandard: String?,
        includeDir: AbsolutePath,
        isTest: Bool = false,
        sources: Sources,
        resources: [Resource] = [],
        dependencies: [Target.Dependency] = [],
        buildSettings: BuildSettings.AssignmentTable = .init()
    ) {
        assert(includeDir.contains(sources.root), "\(includeDir) should be contained in the source root \(sources.root)")
        let type: Kind = isTest ? .test : sources.computeTargetType()
        self.isCXX = sources.containsCXXFiles
        self.cLanguageStandard = cLanguageStandard
        self.cxxLanguageStandard = cxxLanguageStandard
        self.includeDir = includeDir
        super.init(
            name: name,
            bundleName: bundleName,
            defaultLocalization: defaultLocalization,
            platforms: platforms,
            type: type,
            sources: sources,
            resources: resources,
            dependencies: dependencies,
            buildSettings: buildSettings
        )
    }
}

public class BinaryTarget: Target {

    /// The original source of the binary artifact.
    public enum ArtifactSource: Equatable {

        /// Represents an artifact that was downloaded from a remote URL.
        case remote(url: String)

        /// Represents an artifact that was available locally.
        case local
    }

    /// The binary artifact's source.
    public let artifactSource: ArtifactSource

    /// The binary artifact path.
    public var artifactPath: AbsolutePath {
        return sources.root
    }

    public init(
        name: String,
        platforms: [SupportedPlatform] = [],
        path: AbsolutePath,
        artifactSource: ArtifactSource
    ) {
        self.artifactSource = artifactSource
        let sources = Sources(paths: [], root: path)
        super.init(
            name: name,
            defaultLocalization: nil,
            platforms: platforms,
            type: .binary,
            sources: sources,
            dependencies: [],
            buildSettings: .init()
        )
    }
}

extension Target: CustomStringConvertible {
    public var description: String {
        return "<\(Swift.type(of: self)): \(name)>"
    }
}

extension Sources {
    /// Determine target type based on the sources.
    fileprivate func computeTargetType() -> Target.Kind {
        let isLibrary = !relativePaths.contains { path in
            let file = path.basename.lowercased()
            // Look for a main.xxx file avoiding cases like main.xxx.xxx
            return file.hasPrefix("main.") && String(file.filter({$0 == "."})).count == 1
        }
        return isLibrary ? .library : .executable
    }
}
