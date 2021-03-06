function [L,Det]=lmnn(x,y,varargin);
%
% function [L,Det]=lmnn(maxiter,L,x,y,Kg,'Parameter1',Value1,'Parameter2',Value2,...);
%
% Input:
%
% x = input matrix (each column is an input vector) 
% y = labels 
% (*optional*)  L = initial transformation matrix (e.g eye(size(x,1)))
% (*optional*) Kg = attract Kg nearest similar labeled vectos
% 
% Parameters:
% stepsize = (default 1e-09)
% tempid = (def 0) saves state every 10 iterations in temp#.mat
% save = (def 0) save the initial computation 
% skip = (def 0) loads the initial computation instead of
%        recomputing (only works if previous run was on exactly the same data)
% correction = (def 15) how many steps between each update 
%              The number of impostors are fixed for until next "correction"
% factor = (def 1.1) multiplicative factor by which the
%         "correction" gab increases
% obj = (def 1) if 1, solver solves in L, if 0, solver solves in L'*L
% thresho = (def 1e-9) cut off for change in objective function (if
%           improvement is less, stop)
% thresha = (def 1e-22) cut off for stepsize, if stepsize is
%           smaller stop
% validation = (def 0) fraction of training data to be used as
%               validation set (best output is stored in Det.bestL)
% valcount = (def 50) every "valcount" steps do validation
% maxiter = maximum number of iterations (default: 10000)
% scale = (def. 0) if 1, all data gets re-scaled s.t. average
%         distance to closest neighbor is 1
% quiet = {0,1} surpress output (default=0)  
%
%
% Output:
%
% L = linear transformation xnew=L*x
%    
% Det.obj = objective function over time
% Det.nimp = number of impostors over time
% Det.pars = all parameters used in run
% Det.time = time needed for computation
% Det.iter = number of iterations
% Det.verify = verify (results of validation - if used)
%  
% Version 1.0
% copyright by Kilian Q. Weinbergerr (2005)
% University of Pennsylvania
% contact kilianw@seas.upenn.edu
%
  
tempnum=num2str(round(rand(1).*1000));
fprintf('Tempfile: %s\n',tempnum);

fprintf('LMNN stable\n');
if(nargin==0)
 help lmnn;
 return;
end;

if(length(varargin)>0 & isnumeric(varargin{1}))
  % check if neighborhood or L have been passed on
  Kg=varargin{1};
  fprintf('Setting neighborhood to k=%i\n',Kg);
  if(length(varargin)>1 & ~isstr(varargin{2}))
   L=varargin{2};
   fprintf('Setting initial transformation!\n');
  end;
  
  % skip Kgand L parameters
  newvarargin={};copy=0;j=1;
  for i=1:length(varargin)
    if(isstr(varargin{i})) copy=1;end;
    if(copy)newvarargin{j}=varargin{i};j=j+1;end;
  end;
  varargin=newvarargin;  
  clear('newvarargin','copy');
else
 fprintf('Neigborhood size not specified. Setting k=3\n');
 Kg=3;
end;

if(exist('L')~=1)
 fprintf(['Initial starting point not specified.\nStarting with identity matrix.\n']);  
 L=eye(size(x,1));
end;
tic

% checks
D=size(L,2);
x=x(1:D,:);
if(size(x,1)>length(L)) error('x and L must have matching dimensions!\n');end;



 % set parameters
 pars.stepsize=1e-07;
 pars.minstepsize=0;
 pars.tempid=-1;
 pars.save=0;
 pars.skip=0;
 pars.maxiter=10000;
 pars.factor=1.1;
 pars.correction=15;
 pars.thresho=1e-7;
 pars.thresha=1e-22;
 pars.ifraction=1;
 pars.scale=0;
 pars.obj=1;
 pars.union=1;
 pars.tabularasa=Inf;
 pars.quiet=0;
 pars.validation=0;
 pars.validationstep=50;
 pars.earlystopping=0;
 
 pars.aggressive=0;
 pars.valcount=50;
 pars.stepgrowth=1.01;
 pars.reg=0;
 pars.weight1=0.5;
 pars.maximp=100000;
 pars.fifo=0;
 pars.guard=0;
 pars.graphics=0;
 
 
pars=extractpars(varargin,pars);



% verification dataset
%i=randperm(size(x,2));
i=1:size(x,2);
tr=ceil(size(x,2)*(1-pars.validation));
ve=size(x,2)-tr;
xo=x;
yo=y;

x=xo(:,i(1:tr));
y=yo(i(1:tr));
xv=xo(:,i(tr+1:end));
yv=yo(i(tr+1:end));

verify=[];besterr=inf;
clear('xo','yo');
lowesterr=inf;
verify=[];
bestL=L;

if(~pars.quiet)
pars
end;


tempname=sprintf('temp%i.mat',pars.tempid);
% Initializationip
[D,N]=size(x);
fprintf('%i input vectors with %i dimensions\n',N,D);

[gen,NN]=getGenLS(x,y,Kg,pars);
obj=zeros(1,pars.maxiter);
nimp=zeros(1,pars.maxiter);

if(~pars.quiet) fprintf('Total number of genuine pairs: %i\n',size(gen,2));end;

[imp]= checkup(L,x,y,NN(end,:),pars);

if(~pars.quiet)fprintf('Total number of imposture pairs: %i\n',size(imp,2));end;
if(pars.reg==1)
  dfG=vec(eye(D));
else
 dfG=vec(SOD(x,gen(1,:),gen(2,:)));
end;

% Fifo=zeros(1,size(imp,2));

if(pars.scale)
 Lx=L*x;
 sc=sqrt(mean(sum( ((Lx-Lx(:,NN(end,:)))).^2)));
 L=L./sc;
end;

df=zeros(D^2,1);
correction=pars.correction;
tabularasa=pars.tabularasa;
ifraction=pars.ifraction;
stepsize=pars.stepsize;
lastcor=1;

if(pars.graphics)
 hpl=scat(L*x,3,y+0,'size',120);
end;

for nnid=1:Kg; a1{nnid}=[];a2{nnid}=[];end;
df=zeros(size(dfG));

% Main Loop
for iter=1:pars.maxiter
 % save old position
 Lold=L;dfold=df;
 for nnid=1:Kg; a1old{nnid}=a1{nnid};a2old{nnid}=a2{nnid};end;
if(iter>1)L=step(L,mat((dfG.*pars.weight1+df.*(1-pars.weight1))),stepsize,pars);end;


if(~pars.quiet)fprintf('%i.',iter);end;

Lx=L*x;
%Lx2=sum(Lx.^2);
totalactive=0;

if(pars.graphics & mod(iter,10)==0)
 set(hpl,'XData',Lx(1,:),'YData',Lx(2,:));
 set(hpl,'YData',Lx(3,:));
 set(hpl,'CData',y);
 axis tight;
 drawnow;
end;
 

g0=cdist(Lx,imp(1,:),imp(2,:));

if(pars.guard) kk=Kg; 
 else kk=1;
end;
for nnid=kk:Kg
 Ni(nnid,1:N)=(sum((Lx-Lx(:,NN(nnid,:))).^2)+1);
end;


 g1=Ni(:,imp(1,:));
 g2=Ni(:,imp(2,:));
 act1=[];act2=[];

if(pars.validation>0 & (mod(iter,pars.validationstep)==0 | iter==1))
 verify=[verify Ltest2in(Lx,y,L*xv,yv,Ni,Kg,pars)];
 if(verify(end)<=besterr) fprintf('*');besterr=verify(end);bestL= ...
       L;Det.bestiter=iter;
 end;
 if(pars.earlystopping>0 & length(verify)>pars.earlystopping & all(verify(end-pars.earlystopping:end)>besterr)) ...
       fprintf('Validation error is no longer improving!\n');break;
 end;
end;
clear('Lx','Lx2');
 
% objv=dfG'*vec((L'*L));
for nnid=Kg:-1:kk
  act1=find(g0<g1(nnid,:)); 
  act2=find(g0<g2(nnid,:)); 

 active=[act1 act2];

 if(~isempty(a1{nnid}) | ~isempty(a2{nnid}))
try
  [plus1,minus1]=sd(act1(:)',a1{nnid}(:)');
  [plus2,minus2]=sd(act2(:)',a2{nnid}(:)');
catch 
 lasterr
 keyboard;
end;
 else
  plus1=act1;plus2=act2;
  minus1=[];minus2=[];
 end;



% [isminus2,i]=sort(imp(1,minus2));minus2=minus2(i);
 MINUS1a=[imp(1,minus1) imp(2,minus2)]; MINUS1b=[imp(1,[plus1 plus2])];
 MINUS2a=[NN(nnid,imp(1,minus1)) NN(nnid,imp(2,minus2))]; MINUS2b=[imp(2,[plus1 plus2])];

 [isplus2,i]= sort(imp(2,plus2));plus2=plus2(i);
 PLUS1a=[imp(1,plus1) isplus2]; PLUS1b=[imp(1,[minus1 minus2])];
 PLUS2a=[NN(nnid,imp(1,plus1)) NN(nnid,isplus2)]; PLUS2b=[imp(2,[minus1 minus2])];

  loss1=max(g1(nnid,:)-g0,0);
 loss2=max(g2(nnid,:)-g0,0);
 

% ;
 [PLUS ,pweight]=count([PLUS1a;PLUS2a]);
 [MINUS,mweight]=count([MINUS1a;MINUS2a]);


df2=SODW(x,PLUS(1,:),PLUS(2,:),pweight)-SODW(x,MINUS(1,:),MINUS(2,:),mweight);

 df4=SOD(x,PLUS1b,PLUS2b)-SOD(x,MINUS1b,MINUS2b);
 df=df+vec(df2+df4);



 a1{nnid}=act1;a2{nnid}=act2;
 totalactive=totalactive+length(active);

end;



if(any(any(isnan(df))))
  fprintf('Gradient has NaN value!\n');
  keyboard;
end;

%obj(iter)=objv;
obj(iter)=(dfG.*pars.weight1+df.*(1-pars.weight1))'*vec(L'*L)+totalactive.*(1-pars.weight1);

if(isnan(obj(iter)))
 fprintf('Obj is NAN!\n');
 keyboard;
end;

nimp(iter)=totalactive;
delta=obj(iter)-obj(max(iter-1,1));
if(~pars.quiet)fprintf(['  Obj:%2.2f Nimp:%i Delta:%2.4f max(G):' ...
						 ' %2.4f' ...
		    '             \n   '],obj(iter),nimp(iter),delta,max(max(abs(df))));
end;



if(iter>1 & delta>0 & correction~=pars.correction) 
 stepsize=stepsize*0.5;
 fprintf('***correcting stepsize***\n');
 if(stepsize<pars.minstepsize) stepsize=pars.minstepsize;end;
 if(~pars.aggressive)
  L=Lold;
  df=dfold;
  for nnid=1:Kg; a1{nnid}=a1old{nnid};a2{nnid}=a2old{nnid};end;
  obj(iter)=obj(iter-1);
 end;
% correction=1;
 hitwall=1;
else 
  if(correction~=pars.correction)stepsize=stepsize*pars.stepgrowth;end;
 hitwall=0;
end;

if(iter>10  & (max(abs(diff(obj(iter-3:iter))))<pars.thresho*obj(iter) ...
	       | stepsize<pars.thresha)) 
  if(pars.correction-correction>=5) 
     correction=1;
  else
    switch(pars.obj)
     case 0
      if(~pars.quiet)fprintf('Stepsize too small. No more progress!\n');end;
      break;
     case 1
      pars.obj=0;
      pars.correction=15;
      pars.stepsize=1e-9;
      correction=min(correction,pars.correction);
      if(~pars.quiet | 1) 
	fprintf('\nVerifying solution! %i\n',obj(iter)); 
      end;
     case 3
      if(~pars.quiet)fprintf('Stepsize too small. No more progress!\n');end;
      break;
     end;
  end;
 end;

if(pars.tempid>=0 & mod(iter,50)==0) time=toc;save(tempname,'L','iter','obj','pars','time','verify');end;
correction=correction-1;
if(correction==0)
   if(pars.quiet)fprintf('\n');end;
   [Vio]=checkup(L,x,y,NN(nnid,:),pars);

   Vio=setdiff(Vio',imp','rows')';
   if(pars.maximp<inf)
     i=randperm(size(Vio,2));
     Vio=Vio(:,i(1:min(pars.maximp,size(Vio,2))));
   end;
  
   ol=size(imp,2);
    [imp i1 i2]=unique([imp Vio].','rows');
    imp=imp.';
    if(size(imp,2)~=ol)
      for nnid=1:Kg;
	   a1{nnid}=i2(a1{nnid});
	   a2{nnid}=i2(a2{nnid});
      end;
    end;

   
   fprintf('Added %i active constraints. New total: %i\n\n',size(imp,2)-ol,size(imp,2));     
   if(ifraction<1)
     i=1:size(imp,2);
     imp=imp(:,i(1:ceil(length(i)*ifraction)));
     if(~pars.quiet)fprintf('Only use %2.2f of them.\n',ifraction);end;
     ifraction=ifraction+pars.ifraction;
   end;
  
  % put next correction a little more into the future if no new impostors were added
   if(size(imp,2)-ol<=0) 
      pars.correction=min(pars.correction*2+2,300);
      correction=pars.correction-1;
   else
     pars.correction=round(pars.correction*pars.factor);
     correction=pars.correction;
   end;
   lastcor=iter;
end;

end;

% Output
Det.obj=obj(1:iter);
Det.nimp=nimp;
Det.pars=pars;
Det.time=toc;
Det.iter=iter;

Det.verify=verify;

if(pars.validation>0)
 Det.minL=L;
 L=bestL;  
 Det.verify=verify;
end;




function [err,yy,Value]=Ltest2in(Lx,y,LxT,yTest,Ni,Kg,pars);
% function [err,yy,Value]=Ltest2(L,x,y,xTest,yTest,Kg,varargin);
%


% Initializationip
[D,N]=size(Lx);

Lx2=sum(Lx.^2);

MM=min(y);
y=y-MM+1;
un=unique(y);
Value=zeros(length(un),length(yTest));


B=500;
NTe=size(LxT,2);
for n=1:B:NTe
  nn=n:n+min(B-1,NTe-n);
  DD=distance(Lx,LxT(:,nn));  
 for i=1:length(un)
 % Main Loopfor iter=1:pars.maxiter 
  testlabel=un(i);
  
  enemy=find(y~=testlabel);
  friend=find(y==testlabel);

  Df=mink(DD(friend,:),Kg);
  Value(i,nn)=sumiflessv2(DD,Ni(:,enemy),enemy)+sumiflessh2(DD,Df+1,enemy);
  if(pars.reg==0) 
    Value(i,nn)=Value(i,nn)+sum(Df);
  end;  
 end;

end;

 fprintf('\n');
 [temp,yy]=min(Value);

 yy=un(yy)+MM-1;
err=sum(yy~=yTest)./length(yTest);
fprintf('Energy error:%2.2f%%\n',err*100);


function err=validation(Lx,y,LxT,yTest,Ni,Kg);

if(isempty(LxT)) err=0;return;end;
MM=min(y);
y=y-MM+1;
un=unique(y);
Value=zeros(length(un),length(yTest));

B=500;
if(size(Lx,2)>50000) B=250;end;
NTe=size(LxT,2);
for n=1:B:NTe
  fprintf('%2.2f%%: ',n/NTe*100);
  nn=n:n+min(B-1,NTe-n);
  DD=distance(Lx,LxT(:,nn));  
 for i=1:length(un)
  testlabel=un(i);
  fprintf('%i.',testlabel+MM-1);  

  enemy=find(y~=testlabel);
  friend=find(y==testlabel);
  Df=sort(DD(friend,:));
  
  Value(i,nn)=sum(Df(1:Kg,:))+sumiflessv(DD(enemy,:),Ni(enemy))+sumiflessh(DD(enemy,:),Df(Kg,:));
 end;
 fprintf('\n');
end;

 fprintf('\n');
 [temp,yy]=min(Value);

 yy=un(yy)+MM-1;
err=sum(yy~=yTest)./length(yTest);
fprintf('Energy error:%2.2f%%\n',err*100);





function L=step(L,G,stepsize,pars);

% do step in gradient direction
if(size(L,1)~=size(L,2)) pars.obj=1;end;
switch(pars.obj)
  case 0    % updating Q
     Q=L'*L;
     Q=Q-stepsize.*G;
   case 1   % updating L
     G=2.*(L*G);
     L=L-stepsize.*G;     
     return;
  case 2    % multiplicative update
     Q=L'*L;
     Q=Q-stepsize.*G+stepsize^2/4.*G*inv(Q)*G;
     return;
  case 3
     Q=L'*L;
	 Q=Q-stepsize.*G;
	 Q=diag(Q);
 	 L=diag(sqrt(max(Q,0)));
     return;
  otherwise
   error('Objective function has to be 0,1,2\n');
end;

% decompose Q
[L,dd]=eig(Q);
dd=real(diag(dd));
L=real(L);
% reassemble Q (ignore negative eigenvalues)
j=find(dd<1e-10);
if(~isempty(j)) 
    if(~pars.quiet)fprintf('[%i]',length(j));end;
end;
dd(j)=0;
[temp,ii]=sort(-dd);
L=L(:,ii);
dd=dd(ii);
% Q=L*diag(dd)*L';
L=(L*diag(sqrt(dd)))';

%for i=1:size(L,1)
% if(L(i,1)~=0) L(i,:)=L(i,:)./sign(L(i,1));end;
%end;







function imp=getImpLS(x,y,Kg,Ki,pars);
[D,N]=size(x);

filename=sprintf('.LSKInn%i.mat',pars.tempid);
if(pars.skip) load(filename);
else

un=unique(y);
Inn=zeros(Ki,N);
for c=un
  fprintf('%i nearest imposture neighbors for class %i :',Ki,c);
  i=find(y==c);
  j=find(y~=c);
  nn=LSKnn(x(:,j),x(:,i),1:Ki);
  Inn(:,i)=j(nn);
  fprintf('\r');
end;

fprintf('\n');
end;

imp=[vec(Inn(1:Ki,:)')'; vec(repmat(1:N,Ki,1)')'];
imp=unique(imp','rows')'; % Delete dublicates
if(pars.save)
save(filename,'Inn');
end; 



function [gen,NN]=getGenLS(x,y,Kg,pars);
if(~pars.quiet)fprintf('Computing nearest neighbors ...\n');end;
filename=sprintf('.LSKGnn%i.mat',pars.tempid);
[D,N]=size(x);
if(pars.skip) load(filename);
else
un=unique(y);
Gnn=zeros(Kg,N);
for c=un
 fprintf('%i nearest genuine neighbors for class %i:',Kg,c);
 i=find(y==c);
 nn=LSKnn(x(:,i),x(:,i),2:Kg+1);
 Gnn(:,i)=i(nn);
 fprintf('\r');
end;

fprintf('\n');

NN=Gnn;
gen1=vec(Gnn(1:Kg,:)')';
gen2=vec(repmat(1:N,Kg,1)')';

gen=[gen1;gen2];

 if(pars.save)
 save(filename,'gen','NN');
 end; 
end;




function imp=checkup(L,x,y,NN,pars);
if(~pars.quiet)fprintf('Computing nearest neighbors ...\n');end;
[D,N]=size(x);

Lx=L*x;
Ni=sum((Lx-Lx(:,NN)).^2)+1;


un=unique(y);
imp=[];
index=1:N;
for c=un(1:end-1)
 if(~pars.quiet)fprintf('All nearest impostor neighbors for class %i :',c);end;
 i=index(find(y(index)==c));
 index=index(find(y(index)~=c));
 limps=LSImps2(Lx(:,index),Lx(:,i),Ni(index),Ni(i),pars);
 if(size(limps,2)>pars.maximp)
  ip=randperm(size(limps,2));
  ip=ip(1:pars.maximp);
  limps=limps(:,ip);
 end;
 imp=[imp [i(limps(2,:));index(limps(1,:))]];

 if(~pars.quiet)fprintf('\r');end;
end;
try
 imp=unique(sort(imp)','rows')';
catch
 keyboard;  
end;



function limps=LSImps2(X1,X2,Thresh1,Thresh2,pars);
B=750;
[D,N2]=size(X2);
N1=size(X1,2);
limps=[];
for i=1:B:N2
  BB=min(B,N2-i);
  try
  newlimps=findimps3Dac(X1,X2(:,i:i+BB), Thresh1,Thresh2(i:i+BB));
  if(~isempty(newlimps) & newlimps(end)==0)    
    [minv,endpoint]=min(min(newlimps));
    newlimps=newlimps(:,1:endpoint-1);
  end;

  newlimps=unique(newlimps','rows')';
%  if(~all(all(newlimps==newlimps2))) keyboard;end;
%  newlimps2=findimps3D2(X1,X2(:,i:i+BB), Thresh1,Thresh2(i:i+BB));
%  newlimps=unique((sort(newlimps))','rows')';
%  if(length(newlimps2)~=length(newlimps) | ~all(all(newlimps2==newlimps)))
%   keyboard;
%end;
  catch
    keyboard;
    end;
  newlimps(2,:)=newlimps(2,:)+i-1;
  limps=[limps newlimps];
  if(~pars.quiet)fprintf('(%i%%) ',round((i+BB)/N2*100)); end;
end;
if(~pars.quiet)fprintf(' [%i] ',size(limps,2));end;



function NN=LSKnn(X1,X2,ks,pars);
B=750;
[D,N]=size(X2);
NN=zeros(length(ks),N);
DD=zeros(length(ks),N);

for i=1:B:N
  BB=min(B,N-i);
  fprintf('.');
  Dist=distance(X1,X2(:,i:i+BB));
  fprintf('.');
  [dist,nn]=mink(Dist,max(ks));
  clear('Dist');
  fprintf('.'); 
  NN(:,i:i+BB)=nn(ks,:);
  clear('nn','dist');
  fprintf('(%i%%) ',round((i+BB)/N*100)); 
end;
  



