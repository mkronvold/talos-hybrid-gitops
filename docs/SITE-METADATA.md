# Site Metadata System

## Overview

The `.site-metadata` file is the cornerstone of the multi-site architecture in Talos Hybrid GitOps. It provides a **single source of truth** for site-specific configuration, enabling automatic platform detection and eliminating the need to manually specify platform in deployment commands.

## Purpose

The site metadata system serves several critical functions:

1. **Platform Tracking** - Stores whether a site uses vSphere or Proxmox
2. **Automatic Detection** - Scripts read metadata to determine platform automatically
3. **Environment Classification** - Tracks dev/staging/prod environment
4. **Documentation** - Provides human-readable site information
5. **Version Control** - Committed to git for team-wide visibility

## File Location

```
clusters/omni/<site-code>/.site-metadata
```

**Examples:**
- `clusters/omni/ny1d/.site-metadata` - New York Zone 1 Dev
- `clusters/omni/sf2p/.site-metadata` - San Francisco Zone 2 Prod
- `clusters/omni/la1s/.site-metadata` - Los Angeles Zone 1 Staging

## File Format

The `.site-metadata` file is a simple shell-sourceable configuration file:

```bash
# Site Metadata - DO NOT EDIT MANUALLY
SITE_CODE="ny1d"
LOCATION="New York Zone 1"
PLATFORM="vsphere"
ENVIRONMENT="development"
CREATED="2025-12-14T03:18:13+00:00"
```

### Fields

| Field | Description | Example Values | Required |
|-------|-------------|----------------|----------|
| `SITE_CODE` | Site identifier (4 characters) | `ny1d`, `sf2p`, `la1s` | Yes |
| `LOCATION` | Human-readable location name | `"New York Zone 1"` | Yes |
| `PLATFORM` | Infrastructure platform | `vsphere`, `proxmox` | Yes |
| `ENVIRONMENT` | Environment type | `development`, `staging`, `production` | Yes |
| `CREATED` | Timestamp of site creation | ISO 8601 format | Yes |

### Site Code Format

Site codes follow the pattern: `<city><zone><env>`

**Components:**
- `<city>` - 2 lowercase letters (e.g., `ny`, `sf`, `la`, `ch`)
- `<zone>` - Single digit 1-9 (availability zone or region)
- `<env>` - Single letter: `d` (dev), `s` (staging), `p` (prod)

**Examples:**
- `ny1d` → New York, Zone 1, Development
- `sf2p` → San Francisco, Zone 2, Production
- `la1s` → Los Angeles, Zone 1, Staging
- `ch3p` → Chicago, Zone 3, Production

### Environment Mapping

The environment is automatically derived from the site code:

| Code | Environment | Purpose |
|------|-------------|---------|
| `d` | `development` | Dev/test environments |
| `s` | `staging` | Pre-production staging |
| `p` | `production` | Production workloads |

## Creation

Site metadata is automatically created by the `new-site.sh` script:

```bash
./scripts/new-site.sh ny1d vsphere --location "New York Zone 1"
```

This creates:
```
clusters/omni/ny1d/.site-metadata
```

**Do NOT create this file manually.** Always use `new-site.sh` to ensure:
- Proper validation of site code format
- Correct environment detection
- Consistent file format
- Proper directory structure creation

## Usage by Scripts

All deployment scripts automatically load and use site metadata:

### deploy-jumphost.sh

```bash
# Loads platform from metadata
./scripts/deploy-jumphost.sh ny1d

# Internally:
# - Reads clusters/omni/ny1d/.site-metadata
# - Detects PLATFORM=vsphere
# - Uses terraform/jumphost-vsphere/
```

### deploy-infrastructure.sh

```bash
# Loads platform from metadata
./scripts/deploy-infrastructure.sh ny1d clusters/omni/ny1d/web.yaml

# Internally:
# - Reads clusters/omni/ny1d/.site-metadata
# - Detects PLATFORM=vsphere
# - Uses terraform/vsphere/
```

### new-cluster.sh

```bash
# Loads platform from metadata
./scripts/new-cluster.sh ny1d web --control-planes 3 --workers 5

# Internally:
# - Reads clusters/omni/ny1d/.site-metadata
# - Detects PLATFORM=vsphere
# - Sets platform label in cluster YAML
```

## Script Implementation

Scripts load metadata using this pattern:

```bash
# Load site metadata
load_site_metadata() {
    local site_code=$1
    local metadata_file="${PROJECT_ROOT}/clusters/omni/${site_code}/.site-metadata"
    
    if [[ ! -f "$metadata_file" ]]; then
        error "Site metadata not found: $metadata_file"
        error "Site may not exist or was not created with new-site.sh"
        return 1
    fi
    
    source "$metadata_file"
    
    if [[ -z "${PLATFORM:-}" ]]; then
        error "Platform not defined in site metadata"
        return 1
    fi
    
    log "✓ Loaded site metadata: $site_code (platform: $PLATFORM)"
}

# Usage in script
load_site_metadata "$site_code" || exit 1
local platform="$PLATFORM"
```

## Version Control

The `.site-metadata` file **MUST be committed** to git:

✅ **DO:**
- Commit `.site-metadata` files to the repository
- Track changes to site configuration in git history
- Use for team collaboration and documentation

❌ **DON'T:**
- Add `.site-metadata` to `.gitignore`
- Edit manually (use `new-site.sh` to recreate)
- Create without using `new-site.sh`

## Benefits

### 1. Single Source of Truth

Platform is defined once and used everywhere:
```bash
# Site created as vSphere
./scripts/new-site.sh ny1d vsphere --location "New York Zone 1"

# All commands auto-detect vSphere:
./scripts/new-cluster.sh ny1d web
./scripts/deploy-jumphost.sh ny1d
./scripts/deploy-infrastructure.sh ny1d clusters/omni/ny1d/web.yaml
```

### 2. Prevents Platform Mismatch

Before metadata:
```bash
# Risk of mismatch!
./scripts/new-site.sh ny1d vsphere
./scripts/deploy-infrastructure.sh ny1d proxmox  # Wrong platform!
```

After metadata:
```bash
# Platform is consistent
./scripts/new-site.sh ny1d vsphere
./scripts/deploy-infrastructure.sh ny1d  # Correct platform automatically
```

### 3. Team Collaboration

- Platform choice is visible in git
- No need to remember which site uses which platform
- Clear documentation in repository

### 4. Simplified Commands

Before:
```bash
./scripts/deploy-infrastructure.sh ny1d vsphere clusters/omni/ny1d/web.yaml
./scripts/deploy-jumphost.sh ny1d vsphere
```

After:
```bash
./scripts/deploy-infrastructure.sh ny1d clusters/omni/ny1d/web.yaml
./scripts/deploy-jumphost.sh ny1d
```

## Directory Structure

When a site is created, the following structure is generated:

```
clusters/omni/ny1d/
├── .site-metadata          # Platform and site info (committed)
├── README.md              # Site documentation
├── web.yaml              # Cluster configurations
└── data.yaml             # (created by new-cluster.sh)
```

## Validation

Scripts validate metadata integrity:

1. **File Exists Check**
   ```bash
   if [[ ! -f "$metadata_file" ]]; then
       error "Site metadata not found"
       return 1
   fi
   ```

2. **Platform Value Check**
   ```bash
   if [[ -z "${PLATFORM:-}" ]]; then
       error "Platform not defined in site metadata"
       return 1
   fi
   ```

3. **Site Code Format Validation**
   ```bash
   if ! [[ $site_code =~ ^[a-z]{2}[0-9][dsp]$ ]]; then
       error "Invalid site code format"
       return 1
   fi
   ```

## Troubleshooting

### Site metadata not found

**Error:**
```
[ERROR] Site metadata not found: clusters/omni/ny1d/.site-metadata
[ERROR] Site may not exist or was not created with new-site.sh
```

**Solution:**
Create the site first:
```bash
./scripts/new-site.sh ny1d vsphere --location "New York Zone 1"
```

### Platform not defined

**Error:**
```
[ERROR] Platform not defined in site metadata
```

**Solution:**
The `.site-metadata` file is corrupted. Recreate the site:
```bash
# Backup cluster configs
cp -r clusters/omni/ny1d/*.yaml /tmp/

# Remove site directory
rm -rf clusters/omni/ny1d

# Recreate site
./scripts/new-site.sh ny1d vsphere --location "New York Zone 1"

# Restore cluster configs
cp /tmp/*.yaml clusters/omni/ny1d/
```

### Wrong platform detected

**Error:**
Site created as Proxmox but should be vSphere (or vice versa).

**Solution:**
Recreate the site with correct platform:
```bash
# Remove incorrect site
rm -rf clusters/omni/ny1d

# Recreate with correct platform
./scripts/new-site.sh ny1d vsphere --location "New York Zone 1"
```

## Migration from Manual Setup

If you have sites created before the metadata system:

```bash
# For each existing site
SITE_CODE="ny1d"
PLATFORM="vsphere"
LOCATION="New York Zone 1"

# Create metadata file
cat > "clusters/omni/${SITE_CODE}/.site-metadata" <<EOF
# Site Metadata - DO NOT EDIT MANUALLY
SITE_CODE="${SITE_CODE}"
LOCATION="${LOCATION}"
PLATFORM="${PLATFORM}"
ENVIRONMENT="$(echo "$SITE_CODE" | grep -o '[dsp]$' | sed 's/d/development/;s/s/staging/;s/p/production/')"
CREATED="$(date -Iseconds)"
EOF

# Commit to git
git add "clusters/omni/${SITE_CODE}/.site-metadata"
git commit -m "Add metadata for site ${SITE_CODE}"
```

## Examples

### vSphere Production Site

```bash
# clusters/omni/ny1p/.site-metadata
SITE_CODE="ny1p"
LOCATION="New York Zone 1 Production"
PLATFORM="vsphere"
ENVIRONMENT="production"
CREATED="2025-12-14T03:18:13+00:00"
```

### Proxmox Development Site

```bash
# clusters/omni/sf2d/.site-metadata
SITE_CODE="sf2d"
LOCATION="San Francisco Zone 2 Dev"
PLATFORM="proxmox"
ENVIRONMENT="development"
CREATED="2025-12-14T03:18:13+00:00"
```

### Multi-Zone Setup

```bash
# Three zones in LA, all production
clusters/omni/la1p/.site-metadata  # Zone 1
clusters/omni/la2p/.site-metadata  # Zone 2
clusters/omni/la3p/.site-metadata  # Zone 3
```

## Best Practices

1. ✅ **Always use new-site.sh** - Never create `.site-metadata` manually
2. ✅ **Commit to git** - Track site configuration in version control
3. ✅ **Descriptive locations** - Use clear, human-readable location names
4. ✅ **Consistent naming** - Follow site code format strictly
5. ✅ **Document changes** - Update site README when modifying configuration
6. ❌ **Never edit manually** - Recreate site if changes needed
7. ❌ **Don't ignore in git** - Metadata must be tracked
8. ❌ **Don't duplicate** - One site per site code

## Related Documentation

- [new-site.sh documentation](../scripts/README.md#new-sitesh)
- [Site and cluster management](../scripts/README.md#site-and-cluster-management-scripts)
- [Complete workflow examples](../WORKFLOW.md)
- [Quick start guide](QUICKSTART.md)

---

**Last Updated:** 2025-12-14T03:18:13Z
