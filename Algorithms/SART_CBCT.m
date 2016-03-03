function [res,errorL2,rmtotal]=SART_CBCT(proj,geo,alpha,niter,lambda,varargin)
% SART_CBCT solves Cone Beam CT image reconstruction using Oriented Subsets
%              Simultaneous Algebraic Reconxtruction Techique algorithm
%
%   SART_CBCT(PROJ,GEO,ALPHA,NITER) solves the reconstruction problem
%   using the projection data PROJ taken over ALPHA angles, corresponding
%   to the geometry descrived in GEO, using NITER iterations.
%
%   SART_CBCT(PROJ,GEO,ALPHA,NITER,OPT,VAL,...) uses options and values for solving. The
%   possible options in OPT are:
%
%
%   'lambda':      Sets the value of the hyperparameter. Default is 1
%
%   'lambdared':   Reduction of lambda.Every iteration
%                  lambda=lambdared*lambda. Default is 0.95
%
%   'Init':        Describes diferent initialization techniques.
%                  'none'     : Initializes the image to zeros (default)
%                  'FDK'      : intializes image to FDK reconstrucition
%                  'multigrid': Initializes image by solving the problem in
%                               small scale and increasing it when relative
%                               convergence is reached.
%                  'image'    : Initialization using a user specified
%                               image. Not recomended unless you really
%                               know what you are doing.
%   'InitImg'      an image for the 'image' initialization. Aviod.
%
%   'Verbose'      1 or 0. Default is 1. Gives information about the
%                  progress of the algorithm.

%% Deal with input parameters

opts=     {'lambda','Init','InitImg','Verbose','lambdaRed'};
defaults= [  1  ,    1   ,1 ,1,1];

% Check inputs
nVarargs = length(varargin);
if mod(nVarargs,2)
    error('CBCT:SART_CBCT:InvalidInput','Invalid number of inputs')
end

% check if option has been passed as input
for ii=1:2:nVarargs
    ind=find(ismember(opts,varargin{ii}));
    if ~isempty(ind)
        defaults(ind)=0;
    end
end

for ii=1:length(opts)
    opt=opts{ii};
    default=defaults(ii);
    % if one option isnot default, then extranc value from input
   if default==0
        ind=double.empty(0,1);jj=1;
        while isempty(ind)
            ind=find(isequal(opt,varargin{jj}));
            jj=jj+1;
        end
        val=varargin{jj};
    end
    
    switch opt
        % % % % % % % Verbose
        case 'Verbose'
            if default
                verbose=1;
            else
                verbose=val;
            end
        % % % % % % % hyperparameter, LAMBDA
        case 'lambda'
            if default
                lambda=0.95;
            else
                if length(val)>1 || ~isnumeric( val)
                    error('CBCT:SART_CBCT:InvalidInput','Invalid lambda')
                end
                lambda=val;
            end
         case 'lambdaRed'
            if default
                lamdbared=1;
            else
                if length(val)>1 || ~isnumeric( val)
                    error('CBCT:SART_CBCT:InvalidInput','Invalid lambda')
                end
                lamdbared=val;
            end
        case 'Init'
            res=[];
            if default || strcmp(val,'none')
                res=zeros(geo.nVoxel');
                continue;
            end
            if strcmp(val,'FDK')
                res=FDK_CBCT(proj,geo,alpha);
                continue;
            end
            if strcmp(val,'multigrid')
                res=init_multigrid(proj,geo,alpha);
                continue;
            end
            if strcmp(val,'image')
                initwithimage=1;
                continue;
            end
            if isempty(res)
               error('CBCT:SART_CBCT:InvalidInput','Invalid Init option') 
            end
            % % % % % % % ERROR
        case 'InitImg'
            if default
                continue;
            end
            if exist('initwithimage','var');
                if isequal(size(val),geo.nVoxel');
                    res=val;
                else
                    error('CBCT:SART_CBCT:InvalidInput','Invalid image for initialization');
                end
            end
        otherwise
            error('CBCT:SART_CBCT:InvalidInput',['Invalid input name:', num2str(opt),'\n No such option in SART_CBCT()']);
    end
end

errorL2=[];

%% Create weigthing matrices

% Projection weigth, W
W=Ax(ones(geo.nVoxel'),geo,alpha);  % %To get the length of the x-ray inside the object domain
W(W<min(geo.dVoxel)/4)=Inf;
W=1./W;
% Back-Projection weigth, V
[x,y]=meshgrid(geo.sVoxel(1)/2-geo.dVoxel(1)/2+geo.offOrigin(1):-geo.dVoxel(1):-geo.sVoxel(1)/2+geo.dVoxel(1)/2+geo.offOrigin(1),...
    -geo.sVoxel(2)/2+geo.dVoxel(2)/2+geo.offOrigin(2): geo.dVoxel(2): geo.sVoxel(2)/2-geo.dVoxel(2)/2+geo.offOrigin(2));
A = permute(alpha, [1 3 2]);
V = (geo.DSO ./ (geo.DSO + bsxfun(@times, y, sin(-A)) - bsxfun(@times, x, cos(-A)))).^2;
V=sum(V,3);
clear A x y dx dz;

%% Iterate
offOrigin=geo.offOrigin;
offDetector=geo.offDetector;
rmtotal=[];
errorL2=norm(proj(:));
% TODO : Add options for Stopping criteria
for ii=1:niter
    if (ii==1 && verbose==1);tic;end
    for jj=1:length(alpha);
        if size(offOrigin,2)==length(alpha)
            geo.OffOrigin=offOrigin(:,jj);
        end
         if size(offDetector,2)==length(alpha)
            geo.offDetector=offDetector(:,jj);
        end
        proj_err=proj(:,:,jj)-Ax(res,geo,alpha(jj));      %                                 (b-Ax)
        weighted_err=W(:,:,jj).*proj_err;                 %                          W^-1 * (b-Ax)
        backprj=Atb(weighted_err,geo,alpha(jj));          %                     At * W^-1 * (b-Ax)
        weigth_backprj=bsxfun(@times,1./V,backprj);       %                 V * At * W^-1 * (b-Ax)

        res=res+lambda*weigth_backprj;                    % x= x + lambda * V * At * W^-1 * (b-Ax)
        
        rmSART=RMSE(res,res+lambda*weigth_backprj); 
        
        res=res+lambda*weigth_backprj;                    % x= x + lambda * V * At * W^-1 * (b-Ax)
        
        %Store the value of RMSE every iteration
        rmtotal(ii)=[rmSART];
        
    end
    lambda=lambda*lamdbared;

    errornow=norm(proj_err(:));                       % Compute error norm2 of b-Ax
    % If the error is not minimized.
    if  errornow>errorL2(end)
        return;
    end
    errorL2=[errorL2 errornow];

    
    if (ii==1 && verbose==1);
        expected_time=toc*niter;   
        disp('SART');
        disp(['Expected duration  :    ',secs2hms(expected_time)]);
        disp(['Exected finish time:    ',datestr(datetime('now')+seconds(expected_time))]);
        disp('');
    end
end





end

function initres=init_multigrid(proj,geo,alpha)

finalsize=geo.nVoxel;
% start with 64
geo.nVoxel=[64;64;64];
geo.dVoxel=geo.sVoxel./geo.nVoxel;
if any(finalsize<geo.nVoxel)
    initres=zeros(finalsize');
    return;
end
niter=100;
initres=zeros(geo.nVoxel');
while ~isequal(geo.nVoxel,finalsize)
    
    
    % solve subsampled grid
    initres=SART_CBCT(proj,geo,alpha,niter,'Init','image','InitImg',initres,'Verbose',0);
    
    % Get new dims.
    geo.nVoxel=geo.nVoxel*2;
    geo.nVoxel(geo.nVoxel>finalsize)=finalsize(geo.nVoxel>finalsize);
    geo.dVoxel=geo.sVoxel./geo.nVoxel;
    % Upsample!
    % (hopefully computer has enough memory............)
    [y, x, z]=ndgrid(linspace(1,size(initres,1),geo.nVoxel(1)),...
                     linspace(1,size(initres,2),geo.nVoxel(2)),...
                     linspace(1,size(initres,3),geo.nVoxel(3)));
    initres=interp3(initres,x,y,z);
    clear x y z 
end


end
