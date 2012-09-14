classdef RepeatabilityBenchmark < benchmarks.GenericBenchmark ...
    & helpers.Logger & helpers.GenericInstaller
% REPEATABILITYBENCHMARK evaluates the repeatability and matching scores of features
%   REPEATABILITYBENCHMARK('OptionName',optionValue,...)
%   constructs an object to compute the detector repeatabiliy and the
%   descriptor matching scores as given in [1].
%
%   Using this class is a two step process. First, create an instance
%   of the class specifying any parameter needed in the
%   constructor. Then, use TESTFEATURES() to evaluate the scores given
%   a pair of images, the detected features (and optionally their
%   descriptors), and the homography between the two images.
%
%   Use TESTDETECTOR() to evaluate the test for a given detector and
%   pair of images and being able to cache the results of the test.
%
%   DETAILS ON THE REPEATABILITY AND MATCHING SCORES
%
%   The detector repeatability is calculated for two sets of feature
%   frames FRAMESA and FRAMESB detected in a reference image IMAGEA
%   and a second image IMAGEB. The two images are assumed to be
%   related by a known homography H mapping pixels in the domain of
%   IMAGEA to pixels in the domain of IMAGEB (e.g. static camera, no
%   parallax, or moving camera looking at a flat scene). The
%   homography assumes image coordinates with origin in (0,0).
%
%   A perfect co-variant detector would detect the same features in
%   both images regardless of a change in viewpoint (for the features
%   that are visible in both cases). A good detector will also be
%   robust to noise and other distortion. Repeatability is the
%   percentage of detected features that survive a viewpoint change or
%   some other transformation or disturbance in going from IMAGEA to
%   IMAGEB.
%
%   More in detail, repeatability is by default computed as follows:
%
%   1. The elliptical or circular feature frames FRAMEA and FRAMEB,
%      the image sizes SIZEA and SIZEB, and the homography H are
%      obtained.
%
%   2. Features (ellipses or circles) that are fully visible in both
%      images are retained and the others discarded.
%
%   3. For each pair of feature frames A and B, the normalised overlap
%      measure OVERLAP(A,B) is computed. This is defined as the ratio
%      of the area of the intersection over the area of the union of
%      the ellpise/circle FRAMESA(:,A) and FRAMES(:,B) reprojected on
%      IMAGEA by the homography H. Furthermore, after reprojection the
%      size of the ellpises/circles are rescaled so that FRAMESA(:,A)
%      has an area equal to the one of a circle of radius 30 pixels.
%
%   4. Feature are matched optimistically. A candidate match (A,B) is
%      created for every pair of features A,B such that the
%      OVELRAP(A,B) is larger than a certain threshold (defined as 1 -
%      OverlapError) and weighted by OVERLAP(A,B). Then, the final set
%      of matches M={(A,B)} is obtained by performing a greedy
%      bipartite matching between in the weighted graph
%      thus obtained. Greedy means that edges are assigned in order
%      of decreasing overlap.
%
%   5. Repeatability is defined as the ratio of the number of matches
%      M thus obtained and the minimum of the number of features in
%      FRAMESA and FRAMESB:
%
%                                    |M|
%        repeatability = -------------------------.
%                        min(|framesA|, |framesB|)
%
%   RepeatabilityBenchmark can compute the descriptor matching score
%   too (see the 'MatchFramesGeometry' and 'MatchFramesDescriptors'
%   options). To define this, a second set of matches M_d is obtained
%   similarly to the previous method, except that the descriptors
%   distances are used in place of the overlap, no threshold is
%   involved in the genration of canidate matches, and these are
%   selected by increasing descriptor distance rather than by
%   decreasing overlap during greedy bipartite matching. Then the
%   descriptor matching score is defined as:
%
%                              |inters(M,M_d)|
%        matching-score = -------------------------.
%                         min(|framesA|, |framesB|)
%
%   The test behaviour can be adjusted by modifying the following options:
%
%   MatchFramesGeometry:: true
%     Calculate one to one matches based on frames geometry (overlaps).
%
%   MatchFramesDescriptors:: false
%     Create one to one matches based on distances of the image
%     descirptors of frames.
%
%   OverlapError:: 0.4
%     Maximal overlap error of frames to be considered as
%     correspondences.
%
%   NormaliseFrames:: true
%     Normalise the frames to constant scale (defaults is true for
%     detector repeatability tests, see Mikolajczyk et. al 2005).
%
%   NormalisedScale:: 30
%     When frames scale normalisation applied, fixed scale to which it is
%     normalised to.
%
%   CropFrames:: true
%     Crop the frames out of overlaping regions (regions present in both
%     images).
%
%   Magnification:: 3
%     When frames are not normalised, this parameter is magnification
%     applied to the input frames. Usually is equal to magnification
%     factor used for descriptor calculation.
%
%   WarpMethod:: 'standard'
%     Numerical method used for warping ellipses. Available mathods are
%     'standard' and 'km' for precise reproduction of IJCV2005 benchmark
%     results.
%
%   DescriptorsDistanceMetric:: 'L2'
%     Distance metric used for matching the descriptors. See
%     documentation of VL_ALLDIST2 for details.
%
%   REFERENCES
%   [1] K. Mikolajczyk, T. Tuytelaars, C. Schmid, A. Zisserman,
%       J. Matas, F. Schaffalitzky, T. Kadir, and L. Van Gool. A
%       comparison of affine region detectors. IJCV, 1(65):43–72, 2005.

% Author: Karel Lenc, Andrea Vedaldi

% AUTORIGHTS

  properties
    opts = struct(...
      'overlapError', 0.4,...
      'normaliseFrames', true,...
      'cropFrames', true,...
      'magnification', 3,...
      'warpMethod', 'standard',...
      'matchFramesGeometry', true,...
      'matchFramesDescriptors', false,...
      'descriptorsDistanceMetric', 'L2',...
      'normalisedScale', 30);
  end

  properties(Constant)
    keyPrefix = 'repeatability';
  end

  methods
    function obj = RepeatabilityBenchmark(varargin)
      import benchmarks.*;
      import helpers.*;
      obj.benchmarkName = 'repeatability';
      if numel(varargin) > 0
        [obj.opts varargin] = vl_argparse(obj.opts,varargin);
      end
      obj.configureLogger(obj.benchmarkName,varargin);

      if ~obj.isInstalled()
        obj.warn('Benchmark not installed.');
        obj.install();
      end

      if ~obj.opts.matchFramesGeometry && ~obj.opts.matchFramesDescriptors
        obj.error('Invalid options - no way how to match frames.');
      end
    end

    function [score numMatches bestMatches reprojFrames] = ...
                testDetector(obj, detector, tf, imageAPath, imageBPath)
      % TESTDETECTOR Computes the repeatability of a detector on a pair of images
      %   REPEATABILITY = TESTDETECTOR(DETECTOR, TF, IMAGEAPATH, IMAGEBPATH)
      %   computes the repeatability REP of a detector DETECTOR and its
      %   frames extracted from images defined by their path IMAGEAPATH and
      %   IMAGEBPATH whose geometry is related by the homography
      %   transformation TF.
      %
      %   [REPEATABILITY, NUMMATCHES] = TESTDETECTOR(...) returns also the
      %   total number of feature matches found.
      %
      %   This method caches its results, so that calling it again will not
      %   recompute the repeatability score unless the cache is manually
      %   cleared.
      %
      %   See also: RepeatabilityBenchmark().
      import benchmarks.*;
      import helpers.*;

      obj.info('Comparing frames from det. %s and images %s and %s.',...
          detector.detectorName,getFileName(imageAPath),...
          getFileName(imageBPath));

      imageASign = helpers.fileSignature(imageAPath);
      imageBSign = helpers.fileSignature(imageBPath);
      imageASize = helpers.imageSize(imageAPath);
      imageBSize = helpers.imageSize(imageBPath);
      resultsKey = cell2str({obj.keyPrefix, obj.getSignature(), ...
        detector.getSignature(), imageASign, imageBSign});
      cachedResults = obj.loadResults(resultsKey);

      if isempty(cachedResults)
        if obj.opts.matchFramesDescriptors
          [framesA descriptorsA] = detector.extractFeatures(imageAPath);
          [framesB descriptorsB] = detector.extractFeatures(imageBPath);
          [score numMatches bestMatches reprojFrames] = obj.testFeatures(...
            tf, imageASize, imageBSize, framesA, framesB,...
            descriptorsA, descriptorsB);
        else
          [framesA] = detector.extractFeatures(imageAPath);
          [framesB] = detector.extractFeatures(imageBPath);
          [score numMatches bestMatches reprojFrames] = ...
            obj.testFeatures(tf,imageASize, imageBSize,framesA, framesB);
        end
        results = {score numMatches bestMatches reprojFrames};
        obj.storeResults(results, resultsKey);
      else
        [score numMatches bestMatches reprojFrames] = cachedResults{:};
        obj.debug('Results loaded from cache');
      end

    end

    function [score numMatches matches reprojFrames] = ...
                testFeatures(obj, tf, imageASize, imageBSize, ...
                framesA, framesB, descriptorsA, descriptorsB)
      % TESTFEATURES Compute matching score of a given frames and descriptors.
      %   [SCORE NUM_MATCHES] = TESTFEATURES(TF, IMAGE_A_SIZE, IMAGE_B_SIZE,
      %   FRAMES_A, FRAMES_B, DESCS_A, DESCS_B) Compute matching score
      %   SCORE between frames FRAMES_A and FRAMES_B and their
      %   descriptors DESCS_A and DESCS_B which were extracted from
      %   pair of images with sizes IMAGE_A_SIZE and IMAGE_B_SIZE
      %   which geometry is related by homography TF. NUM_MATHCES is
      %   number of matches which is calcuated according to object
      %   settings.
      import benchmarks.helpers.*;
      import helpers.*;

      obj.info('Computing score between %d/%d frames.',...
          size(framesA,2),size(framesB,2));

      if exist('descriptorsA','var') && exist('descriptorsB','var')
        if size(framesA,2) ~= size(descriptorsA,2) ...
            || size(framesB,2) ~= size(descriptorsB,2)
          obj.error('Number of frames and descriptors must be the same.');
        end
      elseif obj.opts.matchFramesDescriptors
        obj.error('Unable to match descriptors without descriptors.');
      end

      startTime = tic;
      normFrames = obj.opts.normaliseFrames;
      overlapError = obj.opts.overlapError;
      overlapThresh = 1 - overlapError;

      % convert frames from any supported format to unortiented
      % ellipses for uniformity
      framesA = localFeatures.helpers.frameToEllipse(framesA) ;
      framesB = localFeatures.helpers.frameToEllipse(framesB) ;

      % map frames from image A to image B and viceversa
      reprojFramesA = warpEllipse(tf, framesA,...
        'Method',obj.opts.warpMethod) ;
      reprojFramesB = warpEllipse(inv(tf), framesB,...
        'Method',obj.opts.warpMethod) ;

      % optionally remove frames that are not fully contained in
      % both images
      if obj.opts.cropFrames
        % find frames fully visible in both images
        bboxA = [1 1 imageASize(2)+1 imageASize(1)+1] ;
        bboxB = [1 1 imageBSize(2)+1 imageBSize(1)+1] ;

        visibleFramesA = isEllipseInBBox(bboxA, framesA ) & ...
          isEllipseInBBox(bboxB, reprojFramesA);

        visibleFramesB = isEllipseInBBox(bboxA, reprojFramesB) & ...
          isEllipseInBBox(bboxB, framesB );

        % Crop frames outside overlap region
        framesA = framesA(:,visibleFramesA);
        reprojFramesA = reprojFramesA(:,visibleFramesA);
        framesB = framesB(:,visibleFramesB);
        reprojFramesB = reprojFramesB(:,visibleFramesB);

        if obj.opts.matchFramesDescriptors
          descriptorsA = descriptorsA(:,visibleFramesA);
          descriptorsB = descriptorsB(:,visibleFramesB);
        end
      end

      if ~normFrames
        % When frames are not normalised, account the descriptor region
        magFactor = obj.opts.magnification^2;
        framesA = [framesA(1:2,:); framesA(3:5,:).*magFactor];
        reprojFramesB = [reprojFramesB(1:2,:); ...
          reprojFramesB(3:5,:).*magFactor];
      end

      reprojFrames = {framesA,framesB,reprojFramesA,reprojFramesB};
      numFramesA = size(framesA,2);
      numFramesB = size(reprojFramesB,2);

      % Find all ellipse overlaps (in one-to-n array)
      frameOverlaps = fastEllipseOverlap(reprojFramesB, framesA, ...
        'NormaliseFrames',normFrames,'MinAreaRatio',overlapThresh,...
        'NormalisedScale',obj.opts.normalisedScale);

      matches = zeros(0, numFramesA) ;

      if obj.opts.matchFramesGeometry
        % Create an edge between each feature in A and in B
        % weighted by the overlap. Each edge is a candidate match.
        corresp = cell(1,numFramesA);
        for j=1:numFramesA
          numNeighs = length(frameOverlaps.scores{j});
          if numNeighs > 0
            corresp{j} = [j *ones(1,numNeighs); ...
                          frameOverlaps.neighs{j}; ...
                          frameOverlaps.scores{j}];
          end
        end
        corresp = cat(2,corresp{:}) ;
        if isempty(corresp)
          score = 0; numMatches = 0; matches = zeros(1,numFramesA); return;
        end

        % Remove edges (candidate matches) that have insufficient overlap
        corresp = corresp(:,corresp(3,:) > overlapThresh) ;
        if isempty(corresp)
          score = 0; numMatches = 0; matches = zeros(1,numFramesA); return;
        end

        % Sort the edgest by decrasing score
        [drop, perm] = sort(corresp(3,:), 'descend');
        corresp = corresp(:, perm);

        % Approximate the best bipartite matching
        obj.info('Matching frames geometry.');
        geometryMatches = greedyBipartiteMatching(numFramesA,...
          numFramesB, corresp(1:2,:)');

        matches = [matches ; geometryMatches];
      end

      if obj.opts.matchFramesDescriptors
        obj.info('Computing cross distances between all descriptors');
        dists = vl_alldist2(single(descriptorsA),single(descriptorsB),...
          obj.opts.descriptorsDistanceMetric);
        obj.info('Sorting distances')
        [dists, perm] = sort(dists(:),'ascend');

        % Create list of edges in the bipartite graph
        [aIdx bIdx] = ind2sub([numFramesA, numFramesB],perm(1:numel(dists)));
        edges = [aIdx bIdx];

        % Find one-to-one best matches
        obj.info('Matching descriptors.');
        descMatches = greedyBipartiteMatching(numFramesA, numFramesB, edges);

        for aIdx=1:numFramesA
          bIdx = descMatches(aIdx);
          [hasCorresp bCorresp] = ismember(bIdx,frameOverlaps.neighs{aIdx});
          % Check whether found descriptor matches fulfill frame overlap
          if ~hasCorresp || ...
             ~frameOverlaps.scores{aIdx}(bCorresp) > overlapThresh
            descMatches(aIdx) = 0;
          end
        end
        matches = [matches ; descMatches];
      end

      % Combine collected matches, i.e. select only equal matches
      validMatches = ...
        prod(single(matches == repmat(matches(1,:),size(matches,1),1)),1);
      matches = matches(1,validMatches~=0);

      % Compute the score
      numBestMatches = sum(matches ~= 0);
      score = numBestMatches / min(size(framesA,2), size(framesB,2));
      numMatches = numBestMatches;

      obj.info('Score: %g \t Num matches: %g', ...
        score,numMatches);

      obj.debug('Score between %d/%d frames comp. in %gs',size(framesA,2), ...
        size(framesB,2),toc(startTime));
    end

    function signature = getSignature(obj)
      signature = helpers.struct2str(obj.opts);
    end
  end

  methods (Static)
    function deps = getDependencies()
      deps = {helpers.Installer(),helpers.VlFeatInstaller('0.9.14'),...
        benchmarks.helpers.Installer()};
    end
  end

end
