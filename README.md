# 🚀 Flux + k3s Bootstrap Guide

This guide describes how to bootstrap a `k3s` Kubernetes cluster with [FluxCD](https://fluxcd.io), configure GPG-based secret encryption with SOPS, and set up a GitHub webhook for GitOps automation.

---

## 0. Set environment variables

```sh
export CLUSTER_NAME="k3s"
export GPG_KEY_NAME="flux $CLUSTER_NAME"
export GPG_KEY_COMMENT="Flux secrets encryption"
export GPG_KEY_EMAIL="sava777+$CLUSTER_NAME@gmail.com"
export GPG_PUBLIC_KEY_FILE="$HOME/${CLUSTER_NAME}.gpg.public"
export GPG_PRIVATE_KEY_FILE="$HOME/${CLUSTER_NAME}.gpg.private"
export GITHUB_TOKEN=ghp_**your_token_here**
export GITHUB_USER=your_github_username
```

---

## 1. Install k3s without Traefik

```sh
curl -sfL https://get.k3s.io | \
K3S_KUBECONFIG_MODE="644" \
INSTALL_K3S_EXEC="--disable traefik" sh -

sudo systemctl status k3s
```

---

## 2. Configure kubectl

```sh
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
kubectl get nodes
```

---

## 3. Install Helm

```sh
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

---

## 4. Install Flux CLI

```sh
curl -s https://fluxcd.io/install.sh | sudo bash
flux --version
```

---

## 5. Create `flux-system` namespace

```sh
kubectl create namespace flux-system
```

---

## 6. Generate GPG key for SOPS encryption

```sh
./script/generate-gpg.sh
```

---

## 7. Prepare cluster directory structure

```sh
mkdir -p ./clusters/${CLUSTER_NAME}/apps
mkdir -p ./clusters/${CLUSTER_NAME}/flux-system
mkdir -p ./clusters/${CLUSTER_NAME}/infra
mkdir -p ./clusters/${CLUSTER_NAME}/receivers

cp -r ./clusters/template/infra/* ./clusters/${CLUSTER_NAME}/infra/
cp -r ./clusters/template/flux-system/kustomization.yaml ./clusters/${CLUSTER_NAME}/flux-system/kustomization.yaml
cp -r ./clusters/template/apps/* ./clusters/${CLUSTER_NAME}/apps/
cp -r ./clusters/template/receivers/* ./clusters/${CLUSTER_NAME}/receivers/
cp ./clusters/template/kustomization.yaml ./clusters/${CLUSTER_NAME}/kustomization.yaml
```

---

## 8. Create GitHub webhook secret for Flux

```sh
TOKEN=$(head -c 12 /dev/urandom | shasum | cut -d ' ' -f1)

kubectl create secret generic github-receiver-token \
  --namespace=flux-system \
  --from-literal=token=${TOKEN} \
  --dry-run=client -o yaml > ./clusters/${CLUSTER_NAME}/receivers/secret-github-receiver-token.yaml

./script/encrypt-secrets.sh ./clusters/${CLUSTER_NAME}/receivers/secret-github-receiver-token.yaml
```

---

## 9. Commit and push changes

```sh
git add .
git commit -m "chore: bootstrap $CLUSTER_NAME"
git push origin master
```

---

## 10. Bootstrap Flux into Git repository

```sh
flux bootstrap git \
  --url="https://github.com/$GITHUB_USER/flux.git" \
  --branch=master \
  --path="clusters/$CLUSTER_NAME" \
  --username="git" \
  --password="$GITHUB_TOKEN"
```

---

## 11. Configure GitHub Webhook

```sh
WH_HOST=$(kubectl -n flux-system get ingress webhook-receiver -o jsonpath='{.spec.rules[0].host}')
WH_PATH=$(kubectl -n flux-system get receiver github-receiver -o jsonpath='{.status.webhookPath}')
echo "URL: https://$WH_HOST$WH_PATH"
echo "Content type: application/json"

WH_SECRET=$(kubectl -n flux-system get secret github-receiver-token -o jsonpath='{.data.token}' | base64 -d; echo)
echo "Secret: $WH_SECRET"
```

* **Payload URL**: `https://<your-domain>/<webhook-path>`
* **Content type**: `application/json`
* **Secret**: value printed above

---

✅ Done! You now have Flux bootstrapped on your k3s cluster with GitOps, SOPS-based secret encryption, and GitHub webhook automation.
