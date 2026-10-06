# Manual QA Testing Checklist

**Run this checklist BEFORE EVERY RELEASE**

Tester: ________________  
Date: ________________  
Version: ________________  
Device: ________________ (include model and Android version)

---

## Core Setup

- [ ] **Install APK** - App installs without errors
- [ ] **First launch** - Owner setup screen shows
- [ ] **Create owner** - Enter name, shop name, 4-digit PIN
- [ ] **PIN validation** - Try invalid PINs (letters, short, long)
- [ ] **Login with correct PIN** - Successful login
- [ ] **Login with wrong PIN** - Shows error
- [ ] **Lockout after 5 attempts** - 30-second lockout works
- [ ] **Auto-lock after 4 min** - App signs out automatically

---

## Product Management

### Add Products
- [ ] **Add product** - All fields save correctly
- [ ] **Empty name** - Shows validation error
- [ ] **Negative price** - Shows validation error
- [ ] **Negative stock** - Shows validation error
- [ ] **Sell below cost** - Shows warning, allows create
- [ ] **Duplicate name** - Shows warning, allows create
- [ ] **Large numbers** - Handles prices > 100,000

### Edit Products
- [ ] **Edit product** - Changes save correctly
- [ ] **Change stock** - Updates immediately
- [ ] **Deactivate product** - Hides from sale list

### Stock Adjustments
- [ ] **Increase stock** - Adjustment recorded
- [ ] **Decrease stock** - Adjustment recorded
- [ ] **Stock goes negative** - Clamps at zero
- [ ] **View adjustments** - Shows in adjustment log

---

## Cash Sales

### Normal Sales
- [ ] **Sell 1 item** - Records correctly
- [ ] **Sell 5 items** - Records correctly
- [ ] **Sell item with 1 stock** - Records, stock goes to 0
- [ ] **Sell multiple of same item** - Totals correct
- [ ] **Remove item from cart** - Updates total
- [ ] **Adjust quantity** - Total recalculates

### Stock Validation
- [ ] **Try to sell more than stock** - Shows error, refuses
- [ ] **Loading cart, out of stock** - Shows error on checkout

### Edge Cases
- [ ] **Empty cart** - Checkout disabled
- [ ] **Double-tap checkout** - Second tap ignored (no double-charge)
- [ ] **Android back button** - No unexpected behavior
- [ ] **Rotate screen** - Cart preserved

---

## M-Pesa Sales (If Enabled)

### Setup
- [ ] **Enable M-Pesa** - Backend registration works
- [ ] **Enter credentials** - Email, password, channel ID
- [ ] **Sync products** - All products get remote IDs
- [ ] **Unsynced product** - M-Pesa shows error

### Payment Flow
- [ ] **Initiate payment** - Reference generated
- [ ] **STK push received** - Phone gets prompt
- [ ] **Customer cancels** - Payment marked FAILED
- [ ] **Insufficient funds** - Payment marked FAILED
- [ ] **Successful payment** - Payment marked SUCCESS
- [ ] **Sale recorded** - Stock decremented
- [ ] **Payment timeout** - Shows timeout message (90s)

### Network Issues
- [ ] **No internet** - M-Pesa disabled, cash works
- [ ] **Weak signal** - Slower but works
- [ ] **Network timeout** - Shows error, can retry

---

## Reports

- [ ] **View today's sales** - Shows correct total
- [ ] **View this week** - Correct date range
- [ ] **View this month** - Correct date range
- [ ] **Filter by staff** - Shows only their sales
- [ ] **Filter by payment** - Cash/M-Pesa split
- [ ] **Profit calculation** - Total profit correct

---

## Inventory Screen

- [ ] **Search products** - Results filter correctly
- [ ] **Sort by name** - Alphabetical order
- [ ] **Sort by stock** - Low stock highlighted
- [ ] **Inactive products** - Show/hide toggle works

---

## Settings (Owner Only)

### Staff Management
- [ ] **Add staff** - New staff appears in login
- [ ] **Staff login** - Can login with PIN
- [ ] **Reset PIN** - New PIN works
- [ ] **Remove staff** - Cannot login, old sales preserved

### Backup/Restore
- [ ] **Export inventory** - .xlsx file created
- [ ] **Share backup** - Can send via WhatsApp/Email
- [ ] **Import backup** - All products restored
- [ ] **Import with conflicts** - Handles duplicates

### Backend Setup
- [ ] **Connect M-Pesa** - Registration completes
- [ ] **Enter channel ID** - Saved correctly
- [ ] **Sync products** - Products uploaded
- [ ] **Disconnect** - Can disable M-Pesa

---

## Interruption Handling

### During Sale
- [ ] **Phone call** - Cart preserved after call
- [ ] **Low battery warning** - Cart preserved
- [ ] **Home button** - App goes to background
- [ ] **Reopen app** - Cart still there
- [ ] **Force close app** - Data consistent on reopen

### During Checkout
- [ ] **Force close mid-transaction** - Stock unchanged
- [ ] **Network lost during M-Pesa** - Payment fails gracefully
- [ ] **App crash during sale** - No corruption

---

## Data Integrity

### Database
- [ ] **Add 50 products** - Performance good
- [ ] **100 sales** - Reports load fast
- [ ] **Large cart (20 items)** - No slowdown

### Migration
- [ ] **Upgrade from older version** - Data preserved
- [ ] **Schema migration** - All columns correct

### Corruption Recovery
- [ ] **Corrupted database** - Shows error screen
- [ ] **Restore from backup** - Recovers successfully

---

## Real Device Testing

**Test on LOW-END Android device:**
- Device model: ________________
- RAM: ________________
- Android version: ________________

- [ ] **Install** - Installs successfully
- [ ] **Launch** - Opens in < 3 seconds
- [ ] **Scrolling** - Smooth scrolling lists
- [ ] **Sale completion** - Completes in < 1 second
- [ ] **Report loading** - Loads in < 2 seconds
- [ ] **Memory pressure** - Doesn't crash with other apps open
- [ ] **Storage full** - Shows error, doesn't corrupt

---

## Localization & Formatting

- [ ] **Currency format** - "KSh 12,500" everywhere
- [ ] **Date format** - Consistent across all screens
- [ ] **Phone numbers** - Kenyan format (07XX XXX XXX)
- [ ] **Large numbers** - Correct comma separators

---

## Edge Cases

- [ ] **Empty inventory** - "No products" message shows
- [ ] **Zero stock** - Shows as "0 in stock"
- [ ] **Negative stock prevented** - Cannot sell negative
- [ ] **Very long product name** - Truncates or wraps
- [ ] **Special characters** - Handles quotes, symbols
- [ ] **Unicode text** - Handles Swahili characters

---

## Performance Testing

- [ ] **App size** - APK < 30 MB
- [ ] **Cold start** - < 3 seconds
- [ ] **Warm start** - < 1 second
- [ ] **Database query** - < 100ms for 100 rows
- [ ] **Report generation** - < 2 seconds for 1 month
- [ ] **M-Pesa timeout** - 90 seconds max

---

## Security

- [ ] **Wrong PIN lockout** - 5 attempts, 30s lockout
- [ ] **Auto sign-out** - After 4 minutes idle
- [ ] **Secure storage** - PIN salt in keystore
- [ ] **No credentials in logs** - Check logcat
- [ ] **HTTPS only** - Network calls encrypted

---

## Installation & Updates

### Fresh Install
- [ ] **Install APK** - No errors
- [ ] **First run** - Setup shows
- [ ] **Permissions** - Granted automatically

### Update Install
- [ ] **Install over existing** - Data preserved
- [ ] **Database migration** - Data intact
- [ ] **Settings preserved** - User prefs saved

### Different Signature
- [ ] **Install different signature** - Shows error
- [ ] **Requires uninstall first** - Data loss warning

---

## Network Conditions

Test with:
- [ ] **WiFi** - All features work
- [ ] **Mobile data** - All features work
- [ ] **Weak signal** - Graceful degradation
- [ ] **No signal** - Offline mode works
- [ ] **Intermittent** - Handles reconnection

---

## Hardware Variations

Test on:
- [ ] **Phone** - Portrait mode
- [ ] **Tablet** - Landscape mode
- [ ] **Small screen** - UI adapts
- [ ] **Large screen** - UI scales

---

## Results Summary

**PASSED:** ___ / ___ tests

**FAILED:** ________________

**BLOCKERS:** ________________

**NOTES:**

_______________

_______________

_______________

---

**Sign-off:** ________________  
**Date:** ________________

**APPROVED FOR RELEASE:** [ ] YES [ ] NO

---

## Pre-Release Final Checks

**Before shipping APK:**

- [ ] All tests above passed
- [ ] Version number updated
- [ ] Changelog updated
- [ ] APK signed with release keystore
- [ ] APK tested on real device
- [ ] Backend deployed and verified
- [ »] Support contact info included
- [ ] Staff training guide printed
- [ ] Owner has backup instructions

**REMEMBER: This app handles real money. Test thoroughly.**
