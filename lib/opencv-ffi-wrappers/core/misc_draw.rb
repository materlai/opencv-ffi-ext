
require 'opencv-ffi-wrappers/core'

module CVFFI

  def self.draw_circle( img, point, opts={} )
    color = opts[:color] || CVFFI::CvScalar.new( {:w=>255, :x=>255, :y=>255, :z=>0} )
    thickness = opts[:thickness] || 5
    radius = opts[:radius] || 1

    CVFFI::cvCircle( img.to_IplImage, point.to_CvPoint, radius, color, thickness,8,0 )
  end

  def self.draw_point( img, point, opts={} )
    opts[:thickness] = -1
    draw_circle( img, point, opts )
  end
end