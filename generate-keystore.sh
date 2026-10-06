#!/bin/bash
# Script to generate a new Android keystore and save base64-encoded version
# Usage: ./generate-keystore.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Android Keystore Generator ===${NC}"
echo ""

# Prompt for inputs
echo -e "${YELLOW}Enter keystore details:${NC}"
read -p "Keystore password: " -s KEYSTORE_PASSWORD
echo ""
read -p "Confirm keystore password: " -s KEYSTORE_PASSWORD_CONFIRM
echo ""

if [ "$KEYSTORE_PASSWORD" != "$KEYSTORE_PASSWORD_CONFIRM" ]; then
  echo -e "${RED}Error: Passwords do not match${NC}"
  exit 1
fi

read -p "Key alias (e.g., 'duka-pos-key'): " KEY_ALIAS
read -p "Your name (for certificate): " CERT_NAME
read -p "Your organization: " CERT_ORG
read -p "Your country code (e.g., KE): " CERT_COUNTRY

echo ""
echo -e "${YELLOW}Generating new keystore...${NC}"

# Generate keystore (365 days validity, or more if needed)
keytool -genkey -v \
  -keystore duka-pos-release.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10950 \
  -alias "$KEY_ALIAS" \
  -storepass "$KEYSTORE_PASSWORD" \
  -keypass "$KEYSTORE_PASSWORD" \
  -dname "CN=$CERT_NAME, O=$CERT_ORG, C=$CERT_COUNTRY" \
  -noprompt

echo -e "${GREEN}✓ Keystore generated: duka-pos-release.jks${NC}"

echo ""
echo -e "${YELLOW}Verifying keystore...${NC}"
keytool -list -keystore duka-pos-release.jks \
  -storepass "$KEYSTORE_PASSWORD" \
  -alias "$KEY_ALIAS"

echo -e "${GREEN}✓ Keystore verified${NC}"

echo ""
echo -e "${YELLOW}Encoding to base64 (no line breaks)...${NC}"
base64 -w 0 duka-pos-release.jks > new
echo -e "${GREEN}✓ Base64-encoded keystore saved to 'new'${NC}"

FILE_SIZE=$(wc -c < new)
echo "File size: $FILE_SIZE bytes"

echo ""
echo -e "${BLUE}=== Done ===${NC}"
echo ""
echo -e "${YELLOW}Your credentials:${NC}"
echo "  Password: $KEYSTORE_PASSWORD"
echo "  Key Alias: $KEY_ALIAS"
echo ""
echo -e "${YELLOW}Files saved:${NC}"
echo "  • duka-pos-release.jks (your keystore - keep this safe!)"
echo "  • new (base64-encoded keystore for GitHub secret)"
echo ""
echo -e "${YELLOW}To update GitHub Secrets:${NC}"
echo "1. Copy the contents of 'new': ${BLUE}cat new${NC}"
echo "2. Go to: https://github.com/zxds1/duka-pos/settings/secrets/actions"
echo "3. Create/Update these secrets:"
echo "   • ANDROID_KEYSTORE_BASE64 = (contents of 'new')"
echo "   • KEYSTORE_PASSWORD = $KEYSTORE_PASSWORD"
echo "   • KEY_ALIAS = $KEY_ALIAS"
echo ""
echo -e "${YELLOW}Copy to clipboard:${NC}"
echo "  macOS: cat new | pbcopy"
echo "  Linux: cat new | xclip -selection clipboard"
echo ""
