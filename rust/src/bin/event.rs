extern crate guestfs;
use guestfs::*;

fn main() {
    for _ in 0..256 {
        let mut g = match Handle::create() {
            Ok(g) => g,
            Err(e) => panic!("could not create handle {:?}", e),
        };
        g.set_event_callback(
            |e, _, _, _| match e {
                Event::Close => print!("c"),
                _ => print!("o"),
            },
            &EVENT_ALL,
        )
        .unwrap();
        let eh = g
            .set_event_callback(|_, _, _, _| print!("n"), &EVENT_ALL)
            .unwrap();
        g.set_trace(true).unwrap();
        g.delete_event_callback(eh).unwrap();
        g.set_trace(false).unwrap();
    }
    let _v = vec![0; 1024 * 1024];
    // no leak
    // mem::forget(v);
    println!()
}
