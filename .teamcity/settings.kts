import ch.fidentity.*
import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildFeatures.perfmon

/*
The settings script is an entry point for defining a TeamCity project hierarchy.
See the other service repositories for the shape this follows; the shared DSL
lives in fidentity/infrastructure under teamcity/teamcity-lib.
*/

version = "2026.1"

project {

    val projectName = "patchmon"
    description = "This project builds and releases the PatchMon Helm chart"

    // There is no image build here. This repository ships only the Helm chart;
    // the container images it deploys are upstream's
    // (ghcr.io/patchmon/patchmon-server) and third-party postgres, redis and
    // guacd. So the release depends on the helm build alone, where the other
    // service repositories also list their docker build.
    val helmBuild = fityBuild("$projectName-helm") {
        name = "helm build"
        description =
            "This build configuration lints the chart, packages it and publishes it to hub.fity.tech/fidentity-charts"

        steps {
            step(fityGoRetagStep { })
            step(fityHelmBuildStep(projectName) { })
        }

        features {
            perfmon { }
        }
    }
    buildType(helmBuild)

    // The release job is based on the helm build, and triggers on tags/*.
    val release = fityRelease(projectName, listOf(helmBuild)) {}
    buildType(release)

}
