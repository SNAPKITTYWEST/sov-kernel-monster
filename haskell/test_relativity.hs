test :: Double
test =
  let m_sun = 1.989e30
      G = 6.674e-11
      c = 299792458.0
      rs = 2.0 * G * m_sun / (c * c)
  in rs
