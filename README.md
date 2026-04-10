# d2-fleet

> [!NOTE]
> This repository is part of the reference architecture for the
> [ControlPlane Enterprise for Flux CD](https://fluxcd.control-plane.io/).
>
> The `d2` reference architecture comprised of
> [d2-fleet](https://github.com/controlplaneio-fluxcd/d2-fleet),
> [d2-infra](https://github.com/controlplaneio-fluxcd/d2-infra) and
> [d2-apps](https://github.com/controlplaneio-fluxcd/d2-apps)
> is a set of best practices and production-ready examples for using Flux Operator
> and OCI Artifacts to manage the continuous delivery of Kubernetes infrastructure and
> applications on multi-cluster multi-tenant environments.
> 
> Download the guide: [Flux D2 Architectural Reference](https://raw.githubusercontent.com/controlplaneio-fluxcd/distribution/main/guides/ControlPlane_Flux_D2_Reference_Architecture_Guide.pdf)

## Scope and Access Control

This repository is managed by the platform team who are responsible for
the Kubernetes infrastructure and have direct access to the fleet of clusters.

The platform team that manages this repository must have **admin** rights to the `d2-fleet` repository
and **cluster admin** rights to all clusters in the fleet to be able to perform the following tasks:

- Bootstrap Flux Operator with multi-tenancy restrictions on the fleet of clusters.
- Configure the delivery of platform components (defined in [d2-infra repository](https://github.com/controlplaneio-fluxcd/d2-infra)).
- Configure the delivery of applications (defined in [d2-apps repository](https://github.com/controlplaneio-fluxcd/d2-apps)).

## OCI Artifacts

The content of the D2 repositories are packaged as OCI Artifacts and published
to GitHub Container Registry using GitHub Actions workflows defined in each repository.
The artifacts are signed with the Cosign keyless procedure using the GitHub Actions OIDC.

Flux running in the clusters, pulls the OCI Artifacts to reconcile the desired state and
verifies the integrity of the content using the Cosign signature. On production clusters,
the artifacts signature subject must match the GitHub repository, Git tag and the
GitHub workflow used to publish the artifact.

### Fleet Artifacts

The artifacts published to `oci://ghcr.io/controlplaneio-fluxcd/d2-fleet` are tagged as:

- `main-<commit-short-sha>` for the main branch commits.
- `latest` points to the latest artifact tagged as `main-<commit-short-sha>`.
- `vX.Y.Z` for the release tags.
- `latest-stable` points to the latest artifact tagged as `vX.Y.Z`.

The Flux Operator running on the Kubernetes clusters in the fleet is configured with a
[FluxInstance](https://github.com/controlplaneio-fluxcd/d2-fleet/blob/main/clusters/staging/flux-system/flux-instance.yaml)
pointing to the OCI Artifact that defines the desired state of each cluster. The staging clusters
are synced from the `latest` tag, while the production clusters are synced from the `latest-stable` tag.

### Components Artifacts

The infrastructure components from `d2-infra` and the applications from `d2-apps` follow the same pattern
and are packaged as OCI Artifacts. The delivery of these components is performed by the Flux Operator
using the [ResourceSet](https://github.com/controlplaneio-fluxcd/d2-fleet/tree/main/tenants) definitions.

Each component is published to a dedicated OCI repository, for example, the `frontend` component
is published to `oci://ghcr.io/controlplaneio-fluxcd/d2-apps/frontend` and is tagged as:

- `latest` for the main branch commits that modify the component.
- `vX.Y.Z` for the release tags matching the Git tag format `<component>/vX.Y.Z`.
- `latest-stable` points to the latest artifact tagged as `vX.Y.Z`.

A component artifact contains the Kubernetes manifests (Flux resources and Kustomize overlays)
that define the desired state of the component for the whole fleet of clusters:

```text
.
├── base
│   ├── kustomization.yaml
│   └── helm-release.yaml
├── production
│   ├── kustomization.yaml
│   └── values-patch.yaml
└── staging
    ├── kustomization.yaml
    └── values-patch.yaml
```

When Flux Operator reconciles the `ResourceSet` for the components, it configures the components tagged
as `latest` to be deployed on the staging clusters, and the ones tagged as
`latest-stable` to be deployed in production.

Rolling back a component in production can be done by moving its `latest-stable` tag to a previous version,
for example, `flux tag oci://ghcr.io/controlplaneio-fluxcd/d2-apps/frontend:v1.2.3 --tag latest-stable`.

The semver tags are considered immutable, while the `latest-stable` tag act as a pointer to the
latest release of the component.

## Bootstrap Procedure

The bootstrap procedure is a one-time operation that installs the Flux Operator on the cluster,
configures the Flux controllers and the delivery of platform components and applications.

After bootstrap, changes to the Flux configuration and version upgrades are done by
modifying the [FluxInstance](https://github.com/controlplaneio-fluxcd/d2-fleet/blob/main/clusters/staging/flux-system/flux-instance.yaml)
manifest and letting Flux reconcile the changes, there is no need to run bootstrap
again nor connect to the cluster.

### GitHub PAT Configuration

It is recommended to create a dedicated GitHub account for the Flux bot. This account will be used
by the Flux source-controller running on clusters to authenticate with GitHub Container Registry
to pull the OCI Artifacts.

The Flux bot account must have read access to the `d2-fleet`, `d2-infra` and `d2-apps` repositories,
and the GitHub [Personal Access Token (classic)](https://github.com/settings/tokens) (PAT) should grant read-only access to the GitHub Container Registry
by selecting the `read:packages` scope.

### Bootstrap a Kubernetes Cluster

For testing purposes, you can create a KinD cluster and bootstrap Flux with the staging configuration
by running the following commands:

```shell
export GITHUB_TOKEN=<Flux Bot PAT>

make bootstrap-staging
```

Another option is to use Terraform or OpenTofu. An example of how to bootstrap a cluster with Terraform
is available in the [terraform](https://github.com/controlplaneio-fluxcd/d2-fleet/tree/main/terraform) directory.

```shell
cd terraform
terraform init
terraform apply \
  -var oci_token="${GITHUB_TOKEN}" \
  -var cluster_name="staging" \
  -var cluster_region="eu-west-2"
```

The bootstrap performs the following steps:

- Creates the `flux-system` namespace.
- Installs the Flux Operator using Helm.
- Creates a `FluxInstance` pointing to the `oci://ghcr.io/controlplaneio-fluxcd/d2-fleet` artifact.
- Creates a Kubernetes image pull secret with the GitHub PAT.

After bootstrap, the Flux Operator Helm release and the Flux instance configuration
are being managed by Flux itself. Any changes to the Flux configuration from now on should be done
by modifying the manifests in the
[flux-system](https://github.com/controlplaneio-fluxcd/d2-fleet/tree/main/clusters/staging/flux-system)
directory.

## Onboarding Platform Components

The platform team is responsible for onboarding the platform components defined as Flux HelmReleases in the
[d2-infra repository](https://github.com/controlplaneio-fluxcd/d2-infra) and set the dependencies
between the components.

Platform components are cluster add-ons such as CRDs and their respective controllers,
and are reconciled by Flux as the **cluster admin**.

To onboard a component from the `d2-infra` repository, the platform team must add a
line for the component in the `.github/workflows/push-artifact.yaml` GitHub Actions
workflow file of the `d2-infra` repository:

```yaml
      ...
      matrix:
        component:
          - cert-manager
          - monitoring
```

With this, an OCI Artifact will be published and signed for the new component.

On the `d2-fleet` repository, the platform team must add a new set of inputs for the
`infra` `ResourceSet`:

```yaml
  ...
  inputs:
    - tenant: "cert-manager"
      tag: "${ARTIFACT_TAG}"
      environment: "${ENVIRONMENT}"
    - tenant: "monitoring"
      tag: "${ARTIFACT_TAG}"
      environment: "${ENVIRONMENT}"
```

With this, the set of base resources for a component will now also be created for the new component.
This set includes an `OCIRepository` object that points to the OCI Artifact, and two `Kustomization`
objects consuming the artifact, `infra-controllers` and `infra-configs`, that together configure the
reconciliation of the new component.

The typical structure of the `d2-infra` repository is as follows:

```shell
./components/
├── cert-manager
│   ├── configs
│   │   ├── base
│   │   ├── production
│   │   └── staging
│   └── controllers
│       ├── base
│       ├── production
│       └── staging
└── monitoring
    ├── configs
    │   ├── base
    │   ├── production
    │   └── staging
    └── controllers
        ├── base
        ├── production
        └── staging
```
