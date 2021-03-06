
require 'nice-ffi'
require 'base64'

require 'opencv-ffi-wrappers'
require 'opencv-ffi-wrappers/misc/params'

require 'opencv-ffi-ext/features2d/keypoint'

module CVFFI

  module Features2D

    # This module calls the cvffi extension library's SIFT functions.
    # The extension's functions, in turn, are re-written versions of OpenCV's SIFT 
    # functions which expose a C API rather than un- and re-wrapping C++
    module SIFT
      extend NiceFFI::Library

      libs_dir = File.dirname(__FILE__) + "/../../../ext/opencv-ffi/"
      pathset = NiceFFI::PathSet::DEFAULT.prepend( libs_dir )
      load_library("cvffi", pathset)

      class CvSIFTParams < NiceFFI::Struct
        layout :octaves, :int,
          :intervals, :int,
          :threshold, :double,
          :edgeThreshold, :double,
          :magnification, :double,
          :recalculateAngles, :int 
      end

      class Params < CVFFI::Params
        param :octaves, 4
        param :intervals, 5 
        param :threshold, 0.04
        param :edgeThreshold, 10.0 
        param :magnification, 3.0
        param :recalculateAngles, 1.0

        def to_CvSIFTParams
          CvSIFTParams.new( @params  )
        end

      end

      class CvFeatureData < NiceFFI::Struct
        include FFI

        layout :r, :int,
          :c, :int,
          :octv, :int,
          :intvl, :int,
          :subintvl, :double,
          :scl_octv, :double

        def self.keys
          [ :r, :c, :octv, :intvl, :subintvl, :scl_octv ]
        end

        def to_a
          CvFeatureData::keys.map { |key| self[key] }
        end

        def self.from_a(a)
          raise "Not enough elements in array to unserialize (#{a.length} < #{keys.length}): #{a.join(',')}" unless a.length >= keys.length

          # This is slightly complicated because FeatureData is referenced as a pointer
          # within CvSIFTFeature.  A copy is made of the CvSIFTFeature while packing the
          # CvSeq, so there are no memory allocation concerns.  However, the CvSIFTFeature
          # retains the pointer to the FeatureData, so we need to explicitly allocate
          # a block of memory and mark it to not be freed when GC'ed.
          pointer = MemoryPointer.new( :uint8, CvFeatureData.size, true )

          # Should prevent the memory from being freed when the Ruby object "pointer" 
          # is released
          pointer.autorelease = false

          feature = CvFeatureData.new( pointer )
          keys.each { |key|
            feature[key] = a.shift
          }
          feature
        end

      end

      ## Unfortunately, the code uses a bespoke "features" structure internally
      # Rather than (for example) CvKeyPoint
      class CvSIFTFeature < NiceFFI::Struct
        layout :x, :double,
               :y, :double,
               :scale, :double,
               :orientation, :double,
               :descriptor_length, :int,
               :descriptor, [ :double, 128 ],
               :feature_data, CvFeatureData.typed_pointer,
               :class_id, :int,
               :response, :float

        def self.keys
          [ :x, :y, :scale, :orientation, :response, :descriptor_length ]
        end

        def self.num_keys
# Extra 1 for descriptor
          keys.length + CvFeatureData.keys.length + 1 
end

        def to_a
          a = CvSIFTFeature::keys.map { |key|
            self[key]
          }
a.push *(feature_data.to_a)
a.push Base64.encode64( descriptor.to_a.pack( "g#{descriptor_length}" ) )
a
        end

        def self.from_a(a)
          raise "Not enough elements in array to unserialize (#{a.length} < #{keys.length}" unless a.length >= keys.length

          feature = CvSIFTFeature.new
          keys.each { |key|
            feature[key] = a.shift
          }

          feature.feature_data = CvFeatureData.from_a a

          desc =  Base64.decode64(a.shift).unpack("g#{feature.descriptor_length}")
          feature.descriptor_length.times { |j| feature[:descriptor][j] = desc[j] }

          feature
        end

        def ==(b)
          result = CvSIFTFeature::keys.reduce( true ) { |m,s|
            puts "Key #{s} doesn't match" unless self[s] == b[s]
            m = m and (self[s] == b[s])
          }

          if descriptor_length > 0 
            result =( result and (descriptor.to_a == b.descriptor.to_a) )
          end

          result
        end
      end

      class Results < SequenceArray
        sequence_class CvSIFTFeature

        def self.coerce( kp, opts ={} )
          case kp
          when SequenceArray, Results
            if kp.sequence_class == CvSIFTFeature
              puts "Asked to coerce SIFT keypoints to SIFT keypoints.  Nice!"
              return kp unless opts[:coerce_sift]
            end
          end

          # Otherwise, must coerce.  
          # TODO:  This is terrible right now...
          keypoints = kp.map { |kp|
            a = CvSIFTFeature.new
            a.x = kp.x
            a.y = kp.y

            a.feature_data = CvFeatureData.new
            a.feature_data.c = a.x * 2
            a.feature_data.r = a.y * 2

            # interval = intvl + subintvl
            # scl      = sigma * 2 ^ (octave + interval/intervals)
            # scl_octv = sigma * 2 ^ (interval/intervals)
            #
            # For sigma = 1.6, octave = 0, interval = 1, intervals = 5
            a.feature_data.octv = 0
            a.feature_data.intvl = 1
            a.feature_data.subintvl = 0.0
            a.scale = a.feature_data.scl_octv = 1.6 * 2 ** (1.0/5)

            a.to_a
          }

          SIFT::Results.from_a( keypoints )
        end
      end


      ## Original C wrappers around OpenCV C++ code
      attach_function :cvSIFTWrapperDetect, [:pointer, :pointer, :pointer, :pointer, CvSIFTParams.by_value ], :void
      attach_function :cvSIFTWrapperDetectDescribe, [:pointer, :pointer, :pointer, :pointer, CvSIFTParams.by_value ], CvMat.typed_pointer

      ## "remixed" OpenCV code which now works directly in C structures
      attach_function :cvSIFTDetect, [:pointer, :pointer, :pointer, 
                              CvSIFTParams.by_value ], CvSeq.typed_pointer

      attach_function :cvSIFTDetectDescribe, [:pointer, :pointer, :pointer, 
                              CvSIFTParams.by_value, :pointer ], CvSeq.typed_pointer

      def self.detect( image, params )
        params = params.to_CvSIFTParams unless params.is_a?( CvSIFTParams )
        storage = CVFFI::cvCreateMemStorage( 0 )
        keypoints = CVFFI::CvSeq.new cvSIFTDetect( image.ensure_greyscale, nil, storage, params )
        Results.new( keypoints, storage )
      end

      def self.detect_describe( image, params, keypoints = nil )
        params = params.to_CvSIFTParams unless params.is_a?( CvSIFTParams )
        if keypoints
          raise "Input must be a SIFT feature sequence not #{keypoints.class}" unless keypoints.is_a?  SequenceArray  and keypoints.sequence_class == CvSIFTFeature

          puts "Sending #{keypoints.length} keypoints"

          # Becase the function works on keypoints in place, must be very
          # careful to not wrap it any other Ruby objects ... which might
          # try to destroy the cvSeq when gc'ed.
          cvSIFTDetectDescribe( image.ensure_greyscale, nil, keypoints.pool, params, keypoints.to_CvSeq )
          keypoints.reset
        else
          storage = CVFFI::cvCreateMemStorage( 0 )
          keypoints = CVFFI::CvSeq.new cvSIFTDetectDescribe( image.ensure_greyscale, nil, storage, params, keypoints )
          Results.new( keypoints, storage )
        end
      end

    end
  end
end
