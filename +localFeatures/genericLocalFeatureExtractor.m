% GENERICDETECTOR Abstract class that defines the interface for a
%   generic affine interest point detector.
%
%   It inherits from the handle class, so that means you can maintain state
%   inside an object of this class. If you have to add your own detector make
%   sure it inherits this class.
%   (see +localFeatures/exampleDetector.m for a simple example)

classdef genericLocalFeatureExtractor < handle
  properties (SetAccess=protected, GetAccess=public)
    isOk = true; % signifies if detector has been installed and runs ok on
                 % this particular platform
  end
  
  properties (SetAccess=public, GetAccess=public)
    detectorName % Set this property in the constructor
  end
  
  properties (Constant)
    keyPrefix = 'det_'; % Prefix of the cached data key
  end

  methods(Abstract)
    % The constructor of every class that inherits from this class
    % is expected to be used to set the options specific to that
    % detector

    [frames descriptors] = extractFeatures(obj, imagePath)
    % EXTRACTFEATURES
    % Expect path to the source image on which the feature extraction
    % should be performed. For caching the results use methods
    % cacheFeatures and loadFeatures.
    %
    % The frames can be of the following format:
    % Output:
    %   frames: 3 x nFrames array storing the output regions as circles
    %     or
    %   frames: 5 x nFrames array storing the output regions as ellipses
    %
    %   frames(1,:) stores the X-coordinates of the points
    %   frames(2,:) stores the Y-coordinates of the points
    %
    %   if frames is 3 x nFrames, then frames(3,:) is the radius of the circles
    %   if frames is 5 x nFrames, then frames(3,:), frames(4,:) and frames(5,:)
    %   store respectively the S11, S12, S22 such that
    %   ELLIPSE = {x: x' inv(S) x = 1}.
    
    sign = getSignature(obj)
    % GETSIGNATURE
    % Returns unique signature for detector parameters.
    %
    % This function is used for caching detected results. When the detector
    % parameters had changed, the signature must be different as well.
 
  end
  
  methods (Access = public)
    function deleteCachedFeatures(obj,imagePath,loadDescriptors)
      import helpers.*;
      
      key = obj.getDataKey(imagePath,loadDescriptors);
      data = DataCache.removeData(key);
    end
  end

  methods (Access = protected)
    function [frames descriptors] = loadFeatures(obj, imagePath,loadDescriptors)
      import helpers.*;
      
      key = obj.getDataKey(imagePath,loadDescriptors);
      data = DataCache.getData(key);
      if ~isempty(data)
        frames = data.frames;
        descriptors = data.descriptors;
        if loadDescriptors
          Log.debug(obj.detectorName,'Frames and descriptors loaded from cache');
        else
          Log.debug(obj.detectorName,'Frames loaded from cache');
        end
      else
        frames = [];
        descriptors = [];
      end
    end
    
    function storeFeatures(obj, imagePath, frames, descriptors)
      hasDescriptors = true;
      if nargin < 4 || isempty(descriptors)
        descriptors = [];
        hasDescriptors = false;
      end
      
      key = obj.getDataKey(imagePath, hasDescriptors);
      data.frames = frames;
      data.descriptors = descriptors;
      helpers.DataCache.storeData(data,key);
    end
    
    function key = getDataKey(obj, imagePath, hasDescriptors)
      import localFeatures.*;
      imageSignature = helpers.fileSignature(imagePath);
      detSignature = obj.getSignature();
      prefix = genericLocalFeatureExtractor.keyPrefix;
      if hasDescriptors
        prefix = strcat(prefix,'+desc');
      end
      key = strcat(prefix,detSignature,imageSignature);
    end

  end % ------- end of methods --------

  methods(Static)
    % Over-ride this function to delete data from the right location
    function cleanDeps()
      fprintf('No dependencies to delete for this detector class\n');
    end

    % Over-ride this function to download and install data in the right location
    function installDeps()
      fprintf('No dependencies to install for this detector class\n');
    end
  end

end % -------- end of class ---------