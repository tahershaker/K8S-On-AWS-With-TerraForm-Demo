# Demo - K8S On AWS With TerraForm Demo

*A series of standalone demos, each focused on one Kubernetes concept or object type, built on top of the cluster provisioned earlier in this repo.*

---

## Description

Each folder below is a self-contained demo covering a single Kubernetes concept — a Pod, a Deployment, storage, networking, and so on. They build on each other loosely (later demos may reuse an image or a pattern from an earlier one), but each has its own README with its own steps.

---

## Intention of Use

This repo demonstrates practical, hands-on Kubernetes knowledge — building and running core concepts one object at a time on a real cluster, rather than in theory only.

**Prerequisite for all demos below:** the cluster must already be provisioned and bootstrapped — see the [Build](/Build/README.md), [Install](/Install/README.md), and [Prep](/Prep/README.MD) steps at the root of this repo.

---

## Demos

| # | Demo | Focus |
|---|---|---|
| 01 | [Deploy Simple Pod](/Demo/01-Deploy-Simple-Pod/README.md) | The Pod object |
| 02 | [Create & Deploy Container From Scratch](/Demo/02-Create-&-Deploy-Container-From-Scratch/README.md) | Building and pushing a custom image, running it as a Pod |
| 03 | [Deploy Google Online Boutique](/Demo/03-Deomply-Google-Online-Boutique/README.md) | A realistic multi-service microservices app |
| 04 | [Expose Simple App](/Demo/04-Expose-Simple-App/README.md) | Services and Ingress |
| 05 | [Deploy Persistent Storage](/Demo/05-Deploy-Persistent-Storage/README.md) | PersistentVolumes and PersistentVolumeClaims |
| 06 | [ConfigMap & Secrets](/Demo/06-ConfigMap-&-Secrets/README.md) | ConfigMaps, Secrets, and how each is consumed by a Pod |

---

Enjoy
