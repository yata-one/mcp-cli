///|
#cfg(all(target="native", not(platform="windows")))
async test "map_limit: respects concurrency + preserves order" {
  let items = [1, 2, 3, 4, 5]
  let mut current = 0
  let mut max = 0
  let results = map_limit(items, 2, fn(x) {
    current = current + 1
    if current > max {
      max = current
    }
    @async.sleep(20)
    current = current - 1
    x * 2
  })
  inspect(results, content="[2, 4, 6, 8, 10]")
  inspect(max, content="2")
}
