# myers_bitparallel.nim
# Myers bit-parallel Levenshtein distance.
# nim c -d:danger -r myers_bitparallel.nim
# Uses the bit-parallel algorithm for patterns up to 64 bytes and falls back
# to dynamic programming for longer patterns.

const MaxBitParallelPattern* = 64

proc levenshteinDp*(a, b: string): int =
  ## Compute edit distance with the classic O(n*m) dynamic-programming method.
  var distances = newSeq[int](b.len + 1)
  for j in 0..b.len:
    distances[j] = j

  for i in 1..a.len:
    var previousDiagonal = distances[0]
    distances[0] = i
    for j in 1..b.len:
      let previousRow = distances[j]
      distances[j] = if a[i - 1] == b[j - 1]:
        previousDiagonal
      else:
        min(previousDiagonal, min(distances[j], distances[j - 1])) + 1
      previousDiagonal = previousRow

  distances[b.len]

proc myers64*(text, pattern: string): int =
  ## Compute edit distance using Myers's bit-parallel algorithm.
  ## The pattern must contain between 1 and 64 bytes.
  let patternLength = pattern.len
  if patternLength < 1 or patternLength > MaxBitParallelPattern:
    raise newException(ValueError, "Pattern length must be between 1 and 64 bytes")

  var characterMasks: array[256, uint64]
  for i in 0..<patternLength:
    let character = pattern[i].uint8
    characterMasks[character] = characterMasks[character] or (1'u64 shl i)

  var positiveVertical: uint64 = not 0'u64
  var negativeVertical: uint64
  var distance = patternLength
  let lastBit = 1'u64 shl (patternLength - 1)

  for character in text:
    let matches = characterMasks[character.uint8]
    let horizontalMatches = matches or negativeVertical
    let horizontalDifferences =
      (((matches and positiveVertical) + positiveVertical) xor positiveVertical) or matches
    var positiveHorizontal = negativeVertical or not (horizontalDifferences or positiveVertical)
    var negativeHorizontal = positiveVertical and horizontalDifferences

    if (positiveHorizontal and lastBit) != 0:
      inc distance
    if (negativeHorizontal and lastBit) != 0:
      dec distance

    positiveHorizontal = (positiveHorizontal shl 1) or 1'u64
    negativeHorizontal = negativeHorizontal shl 1
    negativeVertical = positiveHorizontal and horizontalMatches
    positiveVertical = negativeHorizontal or not (horizontalMatches or positiveHorizontal)

  distance

proc myers*(a, b: string): int =
  ## Return the Levenshtein distance between two byte strings.
  ## The shorter string is used as the bit-parallel pattern.
  if a.len == 0:
    return b.len
  if b.len == 0:
    return a.len

  let (text, pattern) = if a.len >= b.len: (a, b) else: (b, a)
  if pattern.len <= MaxBitParallelPattern:
    myers64(text, pattern)
  else:
    levenshteinDp(text, pattern)

when isMainModule:
  import strformat, strutils, times

  let tests = @[
    ("kitten", "sitting"),
    ("saturday", "sunday"),
    ("nim", "nimble"),
    ("fritzke", "fritzke"),
    ("", "abc"),
  ]

  for (a, b) in tests:
    let expected = levenshteinDp(a, b)
    let actual = myers(a, b)
    echo &"{a} <-> {b}: expected={expected} actual={actual} ok={expected == actual}"

  let longText = "a".repeat(10_000)
  let shortPattern = "abbbbbbbbbb"
  let start = cpuTime()
  discard myers(longText, shortPattern)
  let elapsed = cpuTime() - start
  echo &"\nMyers 10k chars (64-bit pattern): {elapsed * 1000:.3f} ms"
