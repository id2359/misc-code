import os

# Define the path for the journal file
const journalFilePath = "journal.txt"

# Function to add an entry to the journal
proc addEntry(entry: string) =
  let timestamp = getLocalTime()
  let formattedEntry = fmt"{timestamp} - {entry}\n"
  writeFile(journalFilePath, formattedEntry, mode = fmAppend)
  echo "Entry added successfully."

# Function to read and display all journal entries
proc readEntries() =
  if fileExists(journalFilePath):
    let entries = readFile(journalFilePath)
    echo "Journal Entries:"
    echo entries
  else:
    echo "No journal entries found."

# Main loop to handle user input
proc main() =
  while true:
    echo "\nJournal Menu:"
    echo "1. Add Entry"
    echo "2. View Entries"
    echo "3. Exit"
    echo "Choose an option: "
    let choice = readLine(stdin).strip()

    case choice
    of "1":
      echo "Enter your journal entry: "
      let entry = readLine(stdin)
      addEntry(entry)
    of "2":
      readEntries()
    of "3":
      echo "Goodbye!"
      break
    else:
      echo "Invalid option. Please choose again."

main()
