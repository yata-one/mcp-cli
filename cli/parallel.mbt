///|
/// Small async helpers for structured concurrency.

///|
pub async fn[T, U] map_limit(
  items : Array[T],
  limit : Int,
  f : async (T) -> U,
) -> Array[U] {
  @async.with_task_group(fn(group) {
    let sem = @async.Semaphore::new(limit)
    let tasks = items.map(item => group.spawn(fn() {
      sem.acquire()
      defer sem.release()
      f(item)
    }))
    let out = []
    for t in tasks {
      out.push(t.wait())
    }
    out
  })
}
