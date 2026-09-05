//go:build !openharmony && !android
// +build !openharmony,!android

package openp2p

func (t *optun) Stop() (err error) {
	t.stop.Do(func() {
		close(t.done)
		if t.dev != nil {
			err = t.dev.Close()
		}
	})
	t.loops.Wait()
	return err
}
