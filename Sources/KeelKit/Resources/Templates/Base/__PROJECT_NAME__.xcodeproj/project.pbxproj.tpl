// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXFileReference section */
		1A0000000000000000000003 /* __PROJECT_NAME__.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = __PROJECT_NAME__.app; sourceTree = BUILT_PRODUCTS_DIR; };
/* keel:if testing */
		1A0000000000000000000011 /* __PROJECT_NAME__Tests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = __PROJECT_NAME__Tests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
/* keel:end */
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		1A0000000000000000000006 /* __PROJECT_NAME__ */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = __PROJECT_NAME__;
			sourceTree = "<group>";
		};
/* keel:if testing */
		1A0000000000000000000012 /* __PROJECT_NAME__Tests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = __PROJECT_NAME__Tests;
			sourceTree = "<group>";
		};
/* keel:end */
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		1A0000000000000000000008 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* keel:if testing */
		1A0000000000000000000014 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* keel:end */
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		1A0000000000000000000004 = {
			isa = PBXGroup;
			children = (
				1A0000000000000000000006 /* __PROJECT_NAME__ */,
/* keel:if testing */
				1A0000000000000000000012 /* __PROJECT_NAME__Tests */,
/* keel:end */
				1A0000000000000000000005 /* Products */,
			);
			sourceTree = "<group>";
		};
		1A0000000000000000000005 /* Products */ = {
			isa = PBXGroup;
			children = (
				1A0000000000000000000003 /* __PROJECT_NAME__.app */,
/* keel:if testing */
				1A0000000000000000000011 /* __PROJECT_NAME__Tests.xctest */,
/* keel:end */
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		1A0000000000000000000002 /* __PROJECT_NAME__ */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 1A000000000000000000000B /* Build configuration list for PBXNativeTarget "__PROJECT_NAME__" */;
			buildPhases = (
				1A0000000000000000000007 /* Sources */,
				1A0000000000000000000008 /* Frameworks */,
				1A0000000000000000000009 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				1A0000000000000000000006 /* __PROJECT_NAME__ */,
			);
			name = __PROJECT_NAME__;
			productName = __PROJECT_NAME__;
			productReference = 1A0000000000000000000003 /* __PROJECT_NAME__.app */;
			productType = "com.apple.product-type.application";
		};
/* keel:if testing */
		1A0000000000000000000010 /* __PROJECT_NAME__Tests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 1A0000000000000000000016 /* Build configuration list for PBXNativeTarget "__PROJECT_NAME__Tests" */;
			buildPhases = (
				1A0000000000000000000013 /* Sources */,
				1A0000000000000000000014 /* Frameworks */,
				1A0000000000000000000015 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				1A000000000000000000001A /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				1A0000000000000000000012 /* __PROJECT_NAME__Tests */,
			);
			name = __PROJECT_NAME__Tests;
			productName = __PROJECT_NAME__Tests;
			productReference = 1A0000000000000000000011 /* __PROJECT_NAME__Tests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
/* keel:end */
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		1A0000000000000000000001 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {
					1A0000000000000000000002 = {
						CreatedOnToolsVersion = 16.0;
					};
/* keel:if testing */
					1A0000000000000000000010 = {
						CreatedOnToolsVersion = 16.0;
						TestTargetID = 1A0000000000000000000002;
					};
/* keel:end */
				};
			};
			buildConfigurationList = 1A000000000000000000000A /* Build configuration list for PBXProject "__PROJECT_NAME__" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = 1A0000000000000000000004;
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = 1A0000000000000000000005 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				1A0000000000000000000002 /* __PROJECT_NAME__ */,
/* keel:if testing */
				1A0000000000000000000010 /* __PROJECT_NAME__Tests */,
/* keel:end */
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		1A0000000000000000000009 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* keel:if testing */
		1A0000000000000000000015 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* keel:end */
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		1A0000000000000000000007 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* keel:if testing */
		1A0000000000000000000013 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* keel:end */
/* End PBXSourcesBuildPhase section */

/* keel:if testing */
/* Begin PBXContainerItemProxy section */
		1A0000000000000000000019 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 1A0000000000000000000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 1A0000000000000000000002;
			remoteInfo = __PROJECT_NAME__;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXTargetDependency section */
		1A000000000000000000001A /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 1A0000000000000000000002 /* __PROJECT_NAME__ */;
			targetProxy = 1A0000000000000000000019 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */
/* keel:end */

/* Begin XCBuildConfiguration section */
		1A000000000000000000000C /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = __DEPLOYMENT_TARGET__;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 6.0;
			};
			name = Debug;
		};
		1A000000000000000000000D /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = __DEPLOYMENT_TARGET__;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_VERSION = 6.0;
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
		1A000000000000000000000E /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "\"__PROJECT_NAME__/Preview Content\"";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = "__BUNDLE_ID__";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_STRICT_CONCURRENCY = complete;
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		1A000000000000000000000F /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "\"__PROJECT_NAME__/Preview Content\"";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = "__BUNDLE_ID__";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_STRICT_CONCURRENCY = complete;
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
/* keel:if testing */
		1A0000000000000000000017 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = "__BUNDLE_ID__.tests";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_STRICT_CONCURRENCY = complete;
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/__PROJECT_NAME__.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/__PROJECT_NAME__";
			};
			name = Debug;
		};
		1A0000000000000000000018 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = "__BUNDLE_ID__.tests";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_STRICT_CONCURRENCY = complete;
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/__PROJECT_NAME__.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/__PROJECT_NAME__";
			};
			name = Release;
		};
/* keel:end */
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		1A000000000000000000000A /* Build configuration list for PBXProject "__PROJECT_NAME__" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				1A000000000000000000000C /* Debug */,
				1A000000000000000000000D /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		1A000000000000000000000B /* Build configuration list for PBXNativeTarget "__PROJECT_NAME__" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				1A000000000000000000000E /* Debug */,
				1A000000000000000000000F /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* keel:if testing */
		1A0000000000000000000016 /* Build configuration list for PBXNativeTarget "__PROJECT_NAME__Tests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				1A0000000000000000000017 /* Debug */,
				1A0000000000000000000018 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* keel:end */
/* End XCConfigurationList section */
	};
	rootObject = 1A0000000000000000000001 /* Project object */;
}
