% The first version is done by Wenlin
% $Id: spmd_resss.m,v 1.3 2006/10/04 16:06:38 huizhang Exp $

function Vo = spmd_resss(Vi,Vo,R,flags,K)
%
% Create residual sum of squares image (ResSS)
% FORMAT Vo = spmd_resss(Vi,Vo,R,flags)
% Vi          - vector of mapped image volumes to work on (from spm_vol)
% Vo          - handle structure for mapped output image volume
% R           - residual forming matrix
% flags       - 'm' for implicit zero masking
% K           - Smoothing to be applied to data before taking residuals
% Vo (output) - handle structure of output image volume after modifications
%                 for writing
%
% Note that spm_create_image needs to be called external to this function -
% the header is not created!
%_______________________________________________________________________
%
% Residuals are computed as R*Y, where Y is the data vector read from
% images mapped as Vi. The residual sum of squares image (mapped as Vo)
% is written.
%
%-----------------------------------------------------------------------
%
% For a simple linear model Y = X*B * E, with design matrix X,
% (unknown) parameter vector(s) B, and data matrix Y, the least squares
% estimates of B are given by b = inv(X'*X)*X'*Y. If X is rank
% deficient, then the Moore-Penrose pseudoinverse may be used to obtain
% the least squares parameter estimates with the lowest L2 norm: b =
% pinv(X)*Y.
%
% The fitted values are then y = X*b = X*inv(X'*X)*X'*Y, (or
% y=X*pinv(X)*Y). Since the fitted values y are usually known as
% "y-hat", X*inv(X'*X)*X' is known as the "hat matrix" for this model,
% denoted H.
%
% The residuals for this fit (estimates of E) are e = Y - y.
% Substituting from the above, e = (I-H)*Y, where I is the identity
% matrix (see eye). (I-H) is called the residual forming matrix,
% denoted R.
%
% Geometrically, R is a projection matrix, projecting the data into the
% subspace orthogonal to the design space.
%
%                           ----------------
%
% For temporally smoothed fMRI models with convolution matrix K, R is a
% little more complicated:
%          K*Y = K*X * B + K*E
%           KY =  KX * B +  KE
% ...a little working shows that hat matrix is H = KX*inv(KX'*KX)*KX'
% (or KX*pinv(KX)), where KX=K*X. The smoothed residuals KE (=K*E) are
% then given from the temporally smoothed data KY (=K*Y) by y=H*KY.
% Thus the residualising matrix for the temporally smoothed residuals
% from the temporally smoothed data is then (I-H).
%
% Usually the image time series is not temporally smoothed, in which
% case the hat and residualising matrices must incorporate the temporal
% smoothing. The hat matrix for the *raw* (unsmoothed) time series Y is
% H*K, and the corresponding residualising matrix is R=(K-H*K).
% In full, that's
%         R = (K - KX*inv(KX'*KX)*KX'*K)
% or      R = (K - KX*pinv(KX)*K)              when using a pseudoinverse
%
%-----------------------------------------------------------------------
%
% This function can also be used when the b's are images. The residuals
% are then e = Y - X*b, so let Vi refer to the vector of images and
% parameter estimates ([Y;b]), and then R is ([eye(n),-X]), where n is
% the number of Y images.
%
%-----------------------------------------------------------------------
%
% Don't forget to either apply any image scaling (grand mean or
% proportional scaling global normalisation) to the image scalefactors,
% or to combine the global scaling factors in the residual forming
% matrix.
%________________________________ Functions called _____________________
%    spm_type
%    spm_matrix
%    spm_slice_vol
%    spm_filter
%    spm_write_plane
%    spm_close_vol
%    spm_str_mainp
%_______________________________________________________________________
% @(#)spm_resss.m	2.8 Andrew Holmes, John Ashburner 99/06/07
% UM Bios mods
% If Vo is vector of length size(R,1), residuals are written out.
% @(#)spmd_resss.m	1.4 Tom Nichols 02/05/09


%-Argument checks
%-----------------------------------------------------------------------
if nargin<5, K = []; end
if nargin<4, flags=''; end, if isempty(flags), flags='-'; end
mask = any(flags=='m');
if nargin<3, error('insufficient arguments'); end
ni = size(R,2);					%-ni = #images
if ni~=prod(size(Vi)), error('incompatible dimensions'); end
%if ~spm_type(Vo(1).dim(4),'nanrep'), error('only float/double output images supported'), end
if length(Vo)>1 & length(Vo)~=size(R,1),
  error('Vo must be length 1 or size(R,1)'), end

%-Image dimension, orientation and voxel size checks
%-----------------------------------------------------------------------
V = [Vi(:);Vo(:)];
%if any(any(diff(cat(1,V.dim),1,1),1)&[1,1,1,0])	%NB: Bombs for single image
%	error('images don''t all have the same dimensions'), end
if any(any(diff(cat(1,V.dim),1,1),1)&[1,1,0])	%NB: Bombs for single image
	error('images don''t all have the same dimensions'), end
if any(any(any(diff(cat(3,V.mat),1,3),3)))
	error('images don''t all have same orientation & voxel size'), end


%=======================================================================
% - C O M P U T A T I O N
%=======================================================================
fprintf('%-14s%16s',['(',mfilename,')'],'...initialising')	     %-#

Y  = zeros([Vo(1).dim(1:2),ni]);			%-PlaneStack data

im = logical(zeros(ni,1));
%for j=1:ni, im(j)=~spm_type(Vi(j).dim(4),'NaNrep'); end	%-Images without NaNrep

%-Loop over planes computing ResSS
for p=1:Vo(1).dim(3)
	fprintf('%s%16s',repmat(sprintf('\b'),1,16),...
		sprintf('...plane %3d/%-3d',p,Vo(1).dim(3)))       %-#

	M = spm_matrix([0 0 p]);			%-Sampling matrix

	%-Read plane data
	for j=1:ni, Y(:,:,j) = spm_slice_vol(Vi(j),M,Vi(j).dim(1:2),0); end

	%-Apply implicit zero mask for image types without a NaNrep
	if mask, Y(Y(:,:,im)==0)=NaN; end

	if ~isempty(K)
	  e  = R*spm_filter(K,reshape(Y,prod(Vi(1).dim(1:2)),ni)');
	                  				%-residuals as DataMtx
	else
	  e  = R*reshape(Y,prod(Vi(1).dim(1:2)),ni)';	%-residuals as DataMtx
	end

	if length(Vo)>1
	  for i=1:length(Vo)
	    res   = reshape(e(i,:),Vi(1).dim(1:2));	%-Residual plane
	    Vo(i) = spm_write_plane(Vo(i),res,p);	%-Write plane
	  end
	else
	  ss = reshape(sum(e.^2,1),Vi(1).dim(1:2));	%-ResSS plane
	  Vo = spm_write_plane(Vo,ss,p);		%-Write plane
	end
end

%Vo = spm_close_vol(Vo);

%-End
%-----------------------------------------------------------------------
if length(Vo)>1
  tmp = sprintf('...written %s [...]',spm_str_manip(Vo(1).fname,'t'));
else
  tmp = sprintf('...written %s',spm_str_manip(Vo(1).fname,'t'));
end
fprintf('%s%30s\n',repmat(sprintf('\b'),1,30),tmp)        %-#
