#!/bin/bash

# Define the file paths
LEDGER_COREFILE=${LEDGER_COREFILE:-ledger.dat}
LEDGER_PRICEDB=${LEDGER_PRICEDB:-pricedb.dat}

# Check if ledger files exist
if [[ ! -f "$LEDGER_COREFILE" ]]; then
  echo "Error: Ledger core file ($LEDGER_COREFILE) not found."
  exit 1
fi

if [[ ! -f "$LEDGER_PRICEDB" ]]; then
  echo "Error: Price database file ($LEDGER_PRICEDB) not found."
  exit 1
fi

# Function to calculate percentage change
calculate_percentage_change() {
  local current=$1
  local previous=$2

  # Ensure inputs are valid numbers
  if [[ "$current" =~ ^-?[0-9]+([.][0-9]+)?$ ]] && [[ "$previous" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    # Calculate the actual previous balance
    local previous_actual
    previous_actual=$(echo "scale=2; $current - $previous" | bc)

    # Handle cases where previous_actual is zero
    if (( $(echo "$previous_actual == 0" | bc -l) )); then
      if (( $(echo "$previous == 0" | bc -l) )); then
        # No change if both current and previous change are zero
        echo "0.00"
      else
        # Infinite change if previous_actual is zero but there is a change
        echo "Inf"
      fi
    else
      # Standard percentage change calculation
      local change
      change=$(echo "scale=2; ($previous / $previous_actual) * 100" | bc)
      
      # Add "+" sign for positive changes
      if (( $(echo "$change > 0" | bc -l) )); then
        echo "+$change"
      else
        echo "$change"
      fi
    fi
  else
    # Invalid input handling
    echo "0.00"
  fi
}

format_number() {
  local number="$1"
  local integer_part
  local decimal_part

  # Split number into integer and decimal parts
  if [[ "$number" =~ \. ]]; then
    integer_part=$(echo "$number" | cut -d '.' -f 1)
    decimal_part=$(echo "$number" | cut -d '.' -f 2)
    # Ensure decimal part is limited to two digits
    decimal_part=$(printf "%.2f" "0.$decimal_part" | cut -d '.' -f 2)
  else
    integer_part="$number"
    decimal_part="00"
  fi

  # Reverse integer part to add commas in Indian numbering system
  reversed=$(echo "$integer_part" | rev)
  formatted_reversed=$(echo "$reversed" | sed -E ':a;s/^([0-9]{3})([0-9])/\1,\2/;ta')
  formatted=$(echo "$formatted_reversed" | rev)

  # Combine integer and decimal parts
  local formatted_number="${formatted}.${decimal_part}"

  # Append Rs
  echo "${formatted_number} Rs"
}


# Centered and bold title function
print_title() {
  local title=$1
  echo ""
  printf "%-70s\n" "-------------------------------------------------------------------"
  printf "%-70s\n" "$(tput bold)$(printf '%*s' $(( (${#title} + 70) / 2 )) "$title")$(tput sgr0)"
  printf "%-70s\n" "-------------------------------------------------------------------"
}

print_sum_title() {
  local title=$1
  printf "%-70s\n" "$(printf '%*s' $(( (${#title} + 70) / 2 )) "$title")"
}

# Current Date and Report Title
current_date=$(date +"%A, %B %d, %Y")
print_title "JERENS Finance Report - $current_date"

# Fetch and display net worth
current_net_worth=$(ledger -f "$LEDGER_COREFILE" --price-db "$LEDGER_PRICEDB" -V bal assets liabilities | awk 'END{print $NF}')
previous_net_worth=$(ledger -f "$LEDGER_COREFILE" --price-db "$LEDGER_PRICEDB" -V bal assets liabilities --period "yesterday" | awk 'END{print $1}')
net_worth_change=$(calculate_percentage_change "$current_net_worth" "$previous_net_worth")

print_sum_title "Net Worth: $(format_number "$current_net_worth") (($net_worth_change)% change)"

# Account Balances Section
print_title "Account Balances"
printf "%-35s %15s %15s\n" "Account" "Balance" "Change (%)"
printf "%-35s %15s %15s\n" "-----------------------------------" "---------------" "---------------"

declare -A TRACKED_ACCOUNTS=(
  ["Total Assets"]="assets"
  ["Assets (Investments)"]="assets:investments"
  ["Assets (Total Bank Bal)"]="assets:bank"
  ["Assets (Investments Bank Bal)"]="assets:bank:ivaxis"
  ["Assets (Cash Bal)"]="assets:cash"
  ["Total Laibilities"]="liabilities"
  ["Income"]="income"
)

for account in "${!TRACKED_ACCOUNTS[@]}"; do
  current=$(ledger -f "$LEDGER_COREFILE" --price-db "$LEDGER_PRICEDB" -V bal "${TRACKED_ACCOUNTS[$account]}" | awk 'END{print $1}')
  previous=$(ledger -f "$LEDGER_COREFILE" --price-db "$LEDGER_PRICEDB" -V bal "${TRACKED_ACCOUNTS[$account]}" --period "yesterday" | awk 'END{print $1}')
  change=$(calculate_percentage_change "$current" "$previous")
  printf "%-35s %15s %15s\n" "$account" "$(format_number "$current")" "$change"
done

# Investment Details Section
print_title "Investment Details"
printf "%-35s %15s %15s\n" "Investment Account" "Balance" "Change (%)"
printf "%-35s %15s %15s\n" "-----------------------------------" "---------------" "---------------"

declare -A INVESTMENT_ACCOUNTS=(
  ["Mutual Funds"]="assets:investments:mutual_funds"
  ["Stocks"]="assets:investments:stocks"
)

# calculation with original buying price

for investment in "${!INVESTMENT_ACCOUNTS[@]}"; do
  org_current=$(ledger -f "$LEDGER_COREFILE" -B bal "${INVESTMENT_ACCOUNTS[$investment]}" | awk 'END{print $1}')
  current=$(ledger -f "$LEDGER_COREFILE" --price-db "$LEDGER_PRICEDB" -V bal "${INVESTMENT_ACCOUNTS[$investment]}" | awk 'END{print $NF}')
  previous=$(ledger -f "$LEDGER_COREFILE" --price-db "$LEDGER_PRICEDB" -V bal "${INVESTMENT_ACCOUNTS[$investment]}" --period "yesterday" | awk 'END{print $NF}')
  change=$(calculate_percentage_change "$current" "$previous")
  printf "%-35s %15s %15s\n" "$investment" "$(format_number "$current")" "$org_current"
done

# Today's Report Section
print_title "Expense's Report"
today_expense=$(ledger -f "$LEDGER_COREFILE" --price-db "$LEDGER_PRICEDB" -V bal expense --period "today" | awk 'END{print $1}')
m_personal_expense=$(ledger -f "$LEDGER_COREFILE" --price-db "$LEDGER_PRICEDB" -V bal expense:personal --period "this month" | awk 'END{print $NF}')
lm_personal_expense=$(ledger -f "$LEDGER_COREFILE" --price-db "$LEDGER_PRICEDB" -V bal expense:personal --period "last month" | awk 'END{print $NF}')
yesterday_expense=$(ledger -f "$LEDGER_COREFILE" --price-db "$LEDGER_PRICEDB" -V bal expense --period "yesterday" | awk 'END{print $1}')
expense_change=$(calculate_percentage_change "$today_expense" "$yesterday_expense")
m_expense_change=$(calculate_percentage_change "$m_personal_expense" "$lm_personal_expense")
printf "%-35s %15s %15s\n" "Months Personal Expense" "$(format_number "$m_personal_expense")" "$m_expense_change"
printf "%-35s %15s %15s\n" "Today's Expenses" "$(format_number "$today_expense")" "$expense_change"
printf "%-35s %15s\n" "Yesterday's Expenses" "$(format_number "$yesterday_expense")"

echo ""
echo "--------------------------------------------------------------------"
echo "Report generated successfully."
